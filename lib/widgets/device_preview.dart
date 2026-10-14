import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../logic/app_state.dart';
import '../models/device_model.dart';
import '../theme/app_theme.dart';

/// Tile preview of a controller `preview_url` (the box's current JPEG frame).
/// Polls once a second, but only while the tile is on screen, its tab or
/// route is active and the app is in the foreground. On an error the last
/// good frame stays up with an "OFFLINE" badge. A 404 reloads the device
/// list, because device ids change when the controller restarts.
class PolledPreview extends StatefulWidget {
  final String url;
  final BoxFit fit;
  // Drawn over the frame but under the badge, e.g. a gradient for text.
  final Widget? overlay;
  final AlignmentGeometry badgeAlignment;

  const PolledPreview({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.overlay,
    this.badgeAlignment = Alignment.topRight,
  });

  @override
  State<PolledPreview> createState() => _PolledPreviewState();
}

class _PolledPreviewState extends State<PolledPreview> with _JpegFrameDisplay {
  static const Duration _interval = Duration(seconds: 1);
  static const Duration _timeout = Duration(seconds: 3);

  // Shared so every tile reuses connections to the controller.
  static final http.Client _client = http.Client();

  Timer? _timer;
  bool _inFlight = false;
  bool _offline = false;
  ValueListenable<TickerModeData>? _tickerMode;
  Size _screenSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) => _poll());
    // Fetch the first frame right after layout, not a full interval later.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Disabled for hidden tabs (see AppShell) and covered routes.
    _tickerMode = TickerMode.getValuesNotifier(context);
  }

  @override
  void didUpdateWidget(PolledPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isVisible {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    if (!(_tickerMode?.value.enabled ?? true)) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.overlaps(Offset.zero & _screenSize);
  }

  // A fresh `t` on every request so no cache can return an old frame.
  static Uri _cacheBusted(String url) {
    final uri = Uri.parse(url);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
  }

  Future<void> _poll() async {
    if (!mounted || _inFlight || !_isVisible) return;
    _inFlight = true;
    final url = widget.url;
    var shown = false;
    try {
      final response = await _client.get(_cacheBusted(url)).timeout(_timeout);
      if (response.statusCode == 404) {
        unawaited(AppState.instance.refreshDevices());
      }
      if (response.statusCode == 200 && mounted && url == widget.url) {
        shown = await showJpeg(response.bodyBytes);
      }
    } catch (_) {
      // Timeouts and network errors count as offline.
    } finally {
      _inFlight = false;
    }
    if (mounted && url == widget.url && _offline == shown) {
      setState(() => _offline = !shown);
    }
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.sizeOf(context);
    rememberPixelRatio(context);
    final frame = buildFrame(widget.fit);
    if (frame == null) {
      return _offline
          ? PreviewUnavailable(detail: widget.url)
          : const _PreviewLoading();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        frame,
        if (widget.overlay != null) widget.overlay!,
        if (_offline)
          Align(
            alignment: widget.badgeAlignment,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: _OfflineBadge(),
            ),
          ),
      ],
    );
  }
}

/// A device's controller preview, or a placeholder until it has one.
class DeviceThumbnail extends StatelessWidget {
  final Device device;
  final Widget? overlay;
  final AlignmentGeometry badgeAlignment;

  const DeviceThumbnail({
    super.key,
    required this.device,
    this.overlay,
    this.badgeAlignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    final previewUrl = device.previewUrl;
    if (previewUrl != null) {
      return PolledPreview(
        key: ValueKey(device.id),
        url: previewUrl,
        overlay: overlay,
        badgeAlignment: badgeAlignment,
      );
    }

    // Not in the controller's device list (yet).
    return Container(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                color: Colors.grey.shade700,
                size: 28,
              ),
              const SizedBox(height: 4),
              const Text(
                'NO PREVIEW',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen live view of a controller `stream_url` (MJPEG). The stream
/// takes one of the controller's few slots (4 across all phones), so it's
/// closed when this widget goes away or the app goes to the background.
/// If the controller answers 503 (all slots busy) this polls [previewUrl]
/// instead and retries the stream every 30 seconds.
class MjpegStreamView extends StatefulWidget {
  final String streamUrl;
  final String? previewUrl;

  const MjpegStreamView({super.key, required this.streamUrl, this.previewUrl});

  @override
  State<MjpegStreamView> createState() => _MjpegStreamViewState();
}

class _MjpegStreamViewState extends State<MjpegStreamView>
    with _JpegFrameDisplay, WidgetsBindingObserver {
  // Drop buffered bytes if no complete frame shows up within this size.
  static const int _maxBufferBytes = 4 * 1024 * 1024;
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _retryDelay = Duration(seconds: 3);
  static const Duration _busyRetryDelay = Duration(seconds: 30);

  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  Timer? _retryTimer;
  final List<int> _buffer = [];
  bool _busy = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  @override
  void didUpdateWidget(MjpegStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _disconnect();
      _connect();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_client == null) _connect();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _disconnect(); // Frees the stream slot while nobody is watching.
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    final client = http.Client();
    _client = client;
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(widget.streamUrl)))
          .timeout(_connectTimeout);
      if (!identical(_client, client)) return;
      switch (response.statusCode) {
        case 200:
          _sub = response.stream.listen(
            _onChunk,
            onError: (Object e) => _onEnded(client, e),
            onDone: () => _onEnded(client, 'stream closed'),
            cancelOnError: true,
          );
        case 503:
          _disconnect();
          if (!mounted) return;
          setState(() => _busy = true);
          _retryTimer = Timer(_busyRetryDelay, _retry);
        case 404:
          unawaited(AppState.instance.refreshDevices());
          _onEnded(client, 'HTTP 404');
        default:
          _onEnded(client, 'HTTP ${response.statusCode}');
      }
    } catch (e) {
      _onEnded(client, e);
    }
  }

  void _retry() {
    if (mounted) _connect();
  }

  void _onChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    Uint8List? latest;
    while (true) {
      final start = _indexOfMarker(_buffer, 0xD8, 0);
      if (start < 0) {
        _buffer.clear();
        break;
      }
      final end = _indexOfMarker(_buffer, 0xD9, start + 2);
      if (end < 0) {
        if (start > 0) _buffer.removeRange(0, start);
        break;
      }
      latest = Uint8List.fromList(_buffer.sublist(start, end + 2));
      _buffer.removeRange(0, end + 2);
    }
    if (_buffer.length > _maxBufferBytes) _buffer.clear();
    if (latest != null) queueJpeg(latest);
  }

  // Finds the JPEG marker 0xFF <second> at or after [from].
  static int _indexOfMarker(List<int> bytes, int second, int from) {
    for (int i = from; i < bytes.length - 1; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == second) return i;
    }
    return -1;
  }

  @override
  void onFrameShown() {
    if (_busy || _offline) {
      setState(() {
        _busy = false;
        _offline = false;
      });
    }
  }

  void _onEnded(http.Client client, Object reason) {
    if (!identical(_client, client)) return;
    debugPrint('MjpegStreamView: ${widget.streamUrl} ended: $reason');
    _disconnect();
    if (!mounted) return;
    setState(() => _offline = true);
    _retryTimer = Timer(_retryDelay, _retry);
  }

  void _disconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    _buffer.clear();
  }

  @override
  Widget build(BuildContext context) {
    rememberPixelRatio(context);
    final frame = buildFrame(BoxFit.contain);
    final previewUrl = widget.previewUrl;

    final Widget content;
    if (_busy && previewUrl != null) {
      content = PolledPreview(url: previewUrl, fit: BoxFit.contain);
    } else if (frame != null) {
      content = frame;
    } else if (_offline) {
      content = PreviewUnavailable(detail: widget.streamUrl);
    } else {
      content = const _PreviewLoading();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (_busy)
          const Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _Banner(
              'Live view busy: all controller stream slots are in use. '
              'Showing a preview that updates every second.',
            ),
          )
        else if (_offline && frame != null)
          const Positioned(top: 12, right: 12, child: _OfflineBadge()),
      ],
    );
  }
}

/// Decodes JPEG bytes straight into a [ui.Image] sized to the widget and
/// shows the newest one. Skips Flutter's image cache, which would otherwise
/// fill up with full-size frames from a 1 fps poll or a live stream.
mixin _JpegFrameDisplay<T extends StatefulWidget> on State<T> {
  ui.Image? _frame;
  double _pixelRatio = 1;
  Uint8List? _queued;
  bool _decoding = false;

  void rememberPixelRatio(BuildContext context) {
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  /// Decodes and shows [bytes]. Returns false (keeping the current frame)
  /// if they aren't a valid image.
  Future<bool> showJpeg(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _decodeWidth(),
        allowUpscaling: false,
      );
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) {
        image.dispose();
        return false;
      }
      setState(() {
        _frame?.dispose();
        _frame = image;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// For streams: decodes only the newest frame, dropping frames that
  /// arrive while an earlier one is still decoding.
  void queueJpeg(Uint8List bytes) {
    _queued = bytes;
    if (!_decoding) _drainQueue();
  }

  Future<void> _drainQueue() async {
    _decoding = true;
    while (_queued != null && mounted) {
      final bytes = _queued!;
      _queued = null;
      if (await showJpeg(bytes)) onFrameShown();
    }
    _decoding = false;
  }

  /// Called after each queued frame is shown.
  void onFrameShown() {}

  // Wide enough to fill the widget with a 16:9 frame (a cover-fit tile that
  // is taller than 16:9 needs more width than it has) at device resolution.
  int? _decodeWidth() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final logical = math.max(box.size.width, box.size.height * 16 / 9);
    final pixels = (logical * _pixelRatio).ceil();
    return pixels > 0 ? pixels : null;
  }

  Widget? buildFrame(BoxFit fit) {
    final frame = _frame;
    if (frame == null) return null;
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: RawImage(
          image: frame,
          fit: fit,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _frame?.dispose();
    _frame = null;
    super.dispose();
  }
}

/// Error state for a device preview. [detail] (usually the failing URL)
/// makes a screenshot enough to diagnose it. Icon only in small thumbnails.
class PreviewUnavailable extends StatelessWidget {
  final String detail;
  const PreviewUnavailable({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const icon = Icon(Icons.error_outline, color: Colors.white54, size: 20);
          if (constraints.maxHeight < 90) {
            return const Center(child: icon);
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(height: 4),
                  const Text(
                    'PREVIEW UNAVAILABLE',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            color: AppTheme.accentWhite,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: Colors.redAccent),
          SizedBox(width: 4),
          Text(
            'OFFLINE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  const _Banner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
