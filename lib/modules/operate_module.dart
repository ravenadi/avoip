import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../models/device_model.dart';
import '../logic/app_state.dart';
import '../services/av_command_service.dart';
import 'snapshots_module.dart';

class OperateModule extends StatefulWidget {
  const OperateModule({super.key});

  @override
  State<OperateModule> createState() => _OperateModuleState();
}

class _OperateModuleState extends State<OperateModule> {
  ViewMode _viewMode = ViewMode.largeGrid;
  bool _isSourcesView = false;

  Map<String, String?> get _activeRoutes => AppState.instance.activeRoutes;
  List<Device> get _sources => AppState.instance.sources;
  Map<String, List<Device>> get _destinationsByLocation =>
      AppState.instance.destinationsByLocation;

  // ── Shared Source Pool (Allows multiple destinations to share 1 decoder) ──
  final Map<String, VideoPlayerController> _sourcePool = {};
  final Map<String, VideoPlayerController> _sourcePreviewControllers = {};
  final Map<String, bool> _expandedLocations = {};
  String? _selectedDestinationId;

  // Allow all unique decoders to play simultaneously
  bool _initQueueRunning = false;

  List<Device> get _allDestinations =>
      _destinationsByLocation.values.expand((d) => d).toList();

  @override
  void initState() {
    super.initState();
    AppState.instance.initializeSampleData();
    for (final loc in _destinationsByLocation.keys) {
      _expandedLocations[loc] = true;
    }
    // Initialize all source videos upfront
    _initializeAllSources();
    _syncDestControllers();
    AppState.instance.stateVersionNotifier.addListener(_syncDestControllers);
  }

  void _syncDestControllers() {
    // Keep all active source videos playing continuously
    // Don't dispose sources just because they're unrouted
    final Set<String> allSourceIds = _sources.map((s) => s.id).toSet();

    // Only cleanup sources that have been removed from the source list
    final sourcesToDrop =
        _sourcePool.keys
            .where((srcId) => !allSourceIds.contains(srcId))
            .toList();
    for (final srcId in sourcesToDrop) {
      final ctrl = _sourcePool[srcId];
      if (ctrl != null) {
        try {
          ctrl.pause();
        } catch (_) {}
        ctrl.dispose();
        _sourcePool.remove(srcId);
      }
    }

    if (mounted) {
      // Clear image cache to help with thumbnail transitions if needed
      PaintingBinding.instance.imageCache.clear();
      // Always call setState when sync is triggered (e.g. from stateVersionNotifier)
      // This ensures the UI picks up updated routing paths from AppState
      setState(() {});
    }

    // Ensure all sources are playing
    if (!_initQueueRunning) _runInitQueue();
  }

  Future<void> _initializeAllSources() async {
    // Initialize all available sources for continuous playback (Concurrently)
    for (final source in _sources) {
      if (source.videoUrl == null) continue;
      if (_sourcePool.containsKey(source.id)) continue;

      final url = source.videoUrl!;
      final ctrl = url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true))
          : VideoPlayerController.asset(url, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));

      _sourcePool[source.id] = ctrl;

      // Start initialization without awaiting it here, so all start instantly
      ctrl.initialize().timeout(const Duration(seconds: 15)).then((_) {
        if (mounted) {
          ctrl.setLooping(true);
          ctrl.setVolume(0);
          ctrl.play();
          setState(() {});
          debugPrint('✓ Playing: ${source.name}');
        }
      }).catchError((e) {
        debugPrint('✗ Init fail [${source.name}]: $e');
        try {
          ctrl.pause();
        } catch (_) {}
        ctrl.dispose();
        _sourcePool.remove(source.id);
      });
    }
  }

  Future<void> _runInitQueue() async {
    if (_initQueueRunning) return;
    _initQueueRunning = true;

    try {
      // Check all sources to ensure they're playing
      for (final source in _sources) {
        if (source.videoUrl == null) continue;

        // Skip recreating if it already exists in the pool!
        if (_sourcePool.containsKey(source.id)) {
          final ctrl = _sourcePool[source.id];
          if (ctrl != null) {
            // If it's fully initialized but somehow paused, gently resume it
            if (ctrl.value.isInitialized && !ctrl.value.isPlaying) {
              try {
                await ctrl.play();
              } catch (_) {}
            }
            // Do NOT recreate the controller here!
            continue;
          }
        }

        final url = source.videoUrl!;
        final ctrl = url.startsWith('http')
            ? VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true))
            : VideoPlayerController.asset(url, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));

        _sourcePool[source.id] = ctrl;

        // Start initialization without awaiting it here, so all start instantly
        ctrl.initialize().timeout(const Duration(seconds: 15)).then((_) {
          if (mounted) {
            ctrl.setLooping(true);
            ctrl.setVolume(0);
            ctrl.play();
            setState(() {});
            debugPrint('✓ Re-playing: ${source.name}');
          }
        }).catchError((e) {
          debugPrint('✗ Re-init fail [${source.name}]: $e');
          try {
            ctrl.pause();
          } catch (_) {}
          ctrl.dispose();
          _sourcePool.remove(source.id);
        });
      }
    } finally {
      _initQueueRunning = false;
    }
  }

  @override
  void dispose() {
    AppState.instance.stateVersionNotifier.removeListener(_syncDestControllers);
    for (final ctrl in _sourcePool.values) {
      try {
        ctrl.pause();
      } catch (_) {}
      ctrl.dispose();
    }
    _sourcePool.clear();
    for (final ctrl in _sourcePreviewControllers.values) {
      try {
        ctrl.pause();
      } catch (_) {}
      ctrl.dispose();
    }
    _sourcePreviewControllers.clear();
    super.dispose();
  }

  void _changeRoute(String destId, String sourceId) {
    // Update UI state immediately
    AppState.instance.activeRoutes[destId] = sourceId;
    AppState.instance.notifyListeners();

    // Look up the real IPs for TX and RX
    final source = _sources.firstWhere((s) => s.id == sourceId);
    final dest = _allDestinations.firstWhere((d) => d.id == destId);
    debugPrint('[OperateModule] _changeRoute: TX "${source.name}" (${source.id}) ip=${source.ip}  →  RX "${dest.name}" (${dest.id}) ip=${dest.ip}');

    // Fire the hardware command to both TX and RX in the background
    AVCommandService.routeVideo(txIp: source.ip, rxIp: dest.ip).then((success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.bolt_rounded : Icons.warning_amber_rounded,
                color: Colors.black,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  success
                      ? '${source.name} routed to ${dest.name}.'
                      : 'UI updated — hardware unreachable.',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: success ? Colors.greenAccent.shade400 : Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      );
    });
  }

  // Single receiver → /commands/set. Multiple receivers → /commands/set/batch.
  Future<void> _applyMultiRoute(Device source, List<String> destIds) async {
    if (destIds.isEmpty) return;
    final dests = destIds.map((id) => _allDestinations.firstWhere((d) => d.id == id)).toList();
    debugPrint('[OperateModule] _applyMultiRoute: TX "${source.name}" (${source.id}) ip=${source.ip}  →  ${dests.length} receiver(s)');
    for (final dest in dests) {
      debugPrint('[OperateModule]   RX "${dest.name}" (${dest.id}) ip=${dest.ip}');
    }

    final success = dests.length == 1
        ? await AVCommandService.routeVideo(txIp: source.ip, rxIp: dests.first.ip)
        : await AVCommandService.routeVideoBatch(
            txIp: source.ip,
            rxIps: dests.map((d) => d.ip).toList(),
          );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.bolt_rounded : Icons.warning_amber_rounded,
              color: Colors.black,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                success
                    ? '${source.name} routed to ${dests.length} receiver${dests.length == 1 ? '' : 's'}.'
                    : 'UI updated — hardware unreachable.',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: success ? Colors.greenAccent.shade400 : Colors.orangeAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }

  // Tell the backend to stop whatever is currently routed to these receivers.
  Future<void> _stopRoutes(List<String> destIds) async {
    if (destIds.isEmpty) return;
    for (final destId in destIds) {
      final dest = _allDestinations.firstWhere((d) => d.id == destId);
      debugPrint('[OperateModule] _stopRoutes: RX "${dest.name}" (${dest.id}) ip=${dest.ip}');
      await AVCommandService.stopRoute(rxIp: dest.ip);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppState.instance.stateVersionNotifier,
      builder: (context, _, child) {
        final isMobile = MediaQuery.of(context).size.width < 600;
        return Column(
          children: [
            _buildControlHeader(isMobile),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 12 : 20),
                child: _isSourcesView 
                  ? _buildSourcesList(isMobile)
                  : _buildDestinationsList(isMobile),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDestinationsList(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          _destinationsByLocation.entries.map((entry) {
            return _buildLocationGroup(
              entry.key,
              entry.value,
              isMobile,
            );
          }).toList(),
    );
  }

  Widget _buildSourcesList(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active Transmitters',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 400,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 100,
          ),
          itemCount: _sources.length,
          itemBuilder: (context, index) {
            final source = _sources[index];
            final routedCount = _activeRoutes.values.where((v) => v == source.id).length;
            
            return InkWell(
              onTap: () => _showSourceRoutingSheet(source),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.highlightGrey,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cast_rounded, color: Colors.purpleAccent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          Text(source.ip, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: routedCount > 0 ? Colors.greenAccent.withValues(alpha: 0.1) : Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$routedCount Active',
                        style: TextStyle(
                          color: routedCount > 0 ? Colors.greenAccent : Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildControlHeader(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        border: Border(bottom: BorderSide(color: Colors.grey.shade900)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Operate',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isSourcesView ? '${_sources.length} Src' : '${_allDestinations.length} Disp',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SnapshotsModule()));
                },
                icon: const Icon(Icons.auto_awesome_motion_rounded, color: Colors.amberAccent, size: 20),
                tooltip: 'Snapshots',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppTheme.highlightGrey,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _viewModeToggleCap('_isSourcesView', false, isMobile ? 'D' : 'Displays', Icons.monitor),
                    _viewModeToggleCap('_isSourcesView', true, isMobile ? 'S' : 'Sources', Icons.cast),
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 12),
                _buildViewModeSwitcher(),
                const SizedBox(width: 12),
                _buildQuickActions(),
                const SizedBox(width: 12),
                _buildAddButton(false),
              ],
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildViewModeSwitcher(),
                _buildQuickActions(),
                _buildAddButton(true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewModeSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewModeCapsule(ViewMode.largeGrid, Icons.grid_view_rounded),
          Container(width: 1, height: 16, color: Colors.grey.shade800),
          _viewModeCapsule(ViewMode.compactGrid, Icons.grid_on_rounded),
          Container(width: 1, height: 16, color: Colors.grey.shade800),
          _viewModeCapsule(ViewMode.list, Icons.view_list_rounded),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () async {
            final now = DateTime.now();
            await AppState.instance.addSnapshot({
              'title': 'Quick Save ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
              'date': '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}, ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
              'routes': AppState.instance.activeRoutes.length,
              'matrix': Map<String, String?>.from(AppState.instance.activeRoutes),
            });
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Quick Snapshot Created'), behavior: SnackBarBehavior.floating),
              );
            }
          },
          icon: const Icon(Icons.save_outlined, color: Colors.greenAccent, size: 20),
          tooltip: 'Quick Save State',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            if (AppState.instance.savedSnapshots.isNotEmpty) {
              final last = AppState.instance.savedSnapshots.first;
              final dynamic matrixData = last['matrix'];
              if (matrixData != null && matrixData is Map) {
                AppState.instance.loadSnapshotRoutes(Map<String, String?>.from(matrixData));
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Recalled: ${last['title']}'), behavior: SnackBarBehavior.floating),
              );
            }
          },
          icon: const Icon(Icons.history_rounded, color: Colors.blueAccent, size: 20),
          tooltip: 'Recall Last',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildAddButton(bool isMobile) {
    return GestureDetector(
      onTap: _showAddDestinationDialog,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.15), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: Colors.black, size: 16),
            if (!isMobile) ...[
              const SizedBox(width: 6),
              const Text('Add Display', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _viewModeToggleCap(String property, bool value, String label, IconData icon) {
    final isSelected = _isSourcesView == value;
    return InkWell(
      onTap: () => setState(() => _isSourcesView = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade800 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _viewModeCapsule(ViewMode mode, IconData icon) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade800 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? AppTheme.accentWhite : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildLocationGroup(
    String location,
    List<Device> devices,
    bool isMobile,
  ) {
    final isExpanded = _expandedLocations[location] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap:
                () =>
                    setState(() => _expandedLocations[location] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text(
                    location,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${devices.length} display${devices.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child:
                  _viewMode != ViewMode.list
                      ? GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent:
                              _viewMode == ViewMode.largeGrid ? 260 : 160,
                          crossAxisSpacing: isMobile ? 12 : 16,
                          mainAxisSpacing: isMobile ? 12 : 16,
                          mainAxisExtent:
                              _viewMode == ViewMode.largeGrid ? 200 : 180,
                        ),
                        itemCount: devices.length,
                        itemBuilder: (ctx, i) => _buildGridCard(devices[i]),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: devices.length,
                        itemBuilder: (ctx, i) => _buildListCard(devices[i]),
                      ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGridCard(Device dest) {
    final activeSourceId = _activeRoutes[dest.id];
    final activeSource =
        activeSourceId != null
            ? _sources.cast<Device?>().firstWhere(
              (s) => s?.id == activeSourceId,
              orElse: () => null,
            )
            : null;
    final isSelected = _selectedDestinationId == dest.id;

    return GestureDetector(
      onLongPress: () => _showDeleteDeviceDialog(dest),
      onTap: () {
        setState(() {
          if (_selectedDestinationId == dest.id) {
            _selectedDestinationId = null;
          } else {
            _selectedDestinationId = dest.id;
          }
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : Colors.grey.shade800,
            width: isSelected ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  isSelected
                      ? Colors.greenAccent.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.3),
              blurRadius: isSelected ? 15 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              Expanded(child: _buildVideoPreview(dest, activeSource)),
              Container(
                color: Colors.black,
                padding: EdgeInsets.symmetric(
                  horizontal: _viewMode == ViewMode.compactGrid ? 4 : 16,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dest.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _viewMode == ViewMode.compactGrid ? 11 : 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.cast_connected,
                          size: _viewMode == ViewMode.compactGrid ? 9 : 10,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            activeSource?.name ?? 'None',
                            style: TextStyle(
                              color:
                                  activeSource != null
                                      ? Colors.greenAccent
                                      : Colors.grey.shade600,
                              fontSize:
                                  _viewMode == ViewMode.compactGrid ? 10 : 11,
                              fontWeight:
                                  activeSource != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _showSourceSelectionSheet(dest),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Center(
                            child: Text(
                              'Select Source',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListCard(Device dest) {
    final activeSourceId = _activeRoutes[dest.id];
    final activeSource =
        activeSourceId != null
            ? _sources.cast<Device?>().firstWhere(
              (s) => s?.id == activeSourceId,
              orElse: () => null,
            )
            : null;
    final isSelected = _selectedDestinationId == dest.id;

    return GestureDetector(
      onLongPress: () => _showDeleteDeviceDialog(dest),
      onTap: () {
        setState(() {
          if (_selectedDestinationId == dest.id) {
            _selectedDestinationId = null;
          } else {
            _selectedDestinationId = dest.id;
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : Colors.grey.shade800,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _buildVideoPreview(
                    dest,
                    activeSource,
                    showOverlay: false,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dest.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.cast_connected,
                          size: 12,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            activeSource?.name ?? 'No Source',
                            style: TextStyle(
                              color:
                                  activeSource != null
                                      ? Colors.greenAccent
                                      : Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight:
                                  activeSource != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _showSourceSelectionSheet(dest),
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Select Source',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDeviceDialog(Device dest) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Remove Display', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove "${dest.name}" from ${dest.location}?',
          style: TextStyle(color: Colors.grey.shade300),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              if (_selectedDestinationId == dest.id) {
                setState(() => _selectedDestinationId = null);
              }
              await AppState.instance.removeDevice(dest.id, dest.location);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Removed ${dest.name}')),
                );
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview(
    Device dest,
    Device? routedSource, {
    bool showOverlay = true,
  }) {
    final ctrl = (routedSource != null) ? _sourcePool[routedSource.id] : null;

    if (routedSource != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          (ctrl != null && ctrl.value.isInitialized)
              ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: ctrl.value.size.width,
                  height: ctrl.value.size.height,
                  child: VideoPlayer(ctrl),
                ),
              )
              : Container(
                color: Colors.black,
                child: Center(
                  child:
                      (ctrl != null && ctrl.value.hasError)
                          ? Icon(
                            Icons.broken_image_outlined,
                            color: Colors.grey.shade800,
                            size: 32,
                          )
                          : const CircularProgressIndicator(
                            color: AppTheme.accentWhite,
                            strokeWidth: 2,
                          ),
                ),
              ),
          if (showOverlay)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          if (showOverlay && routedSource != null)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  routedSource.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      color: Colors.grey.shade900,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_outlined, size: 24, color: Colors.grey.shade700),
            if (showOverlay) ...[
              const SizedBox(height: 4),
              const Text(
                'NO SIGNAL',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSourceRoutingSheet(Device source) {
    final Map<String, bool> selectedDests = {};
    for (final dest in _allDestinations) {
      selectedDests[dest.id] = _activeRoutes[dest.id] == source.id;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: AppTheme.backgroundLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Route ${source.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('Select receivers to switch to this source', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final destIdsToRoute = <String>[];
                        final destIdsToStop = <String>[];
                        for (final entry in selectedDests.entries) {
                          if (entry.value) {
                            AppState.instance.activeRoutes[entry.key] = source.id;
                            destIdsToRoute.add(entry.key);
                          } else if (_activeRoutes[entry.key] == source.id) {
                            AppState.instance.activeRoutes[entry.key] = null;
                            destIdsToStop.add(entry.key);
                          }
                        }
                        AppState.instance.notifyListeners();
                        Navigator.pop(ctx);
                        _applyMultiRoute(source, destIdsToRoute);
                        _stopRoutes(destIdsToStop);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Apply Routes', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _destinationsByLocation.entries.map((group) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Text(group.key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 12)),
                        ),
                        ...group.value.map((dest) {
                          final isSelected = selectedDests[dest.id] ?? false;
                          return CheckboxListTile(
                            title: Text(dest.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(dest.ip, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            value: isSelected,
                            activeColor: Colors.greenAccent,
                            checkColor: Colors.black,
                            onChanged: (val) => setModalState(() => selectedDests[dest.id] = val ?? false),
                          );
                        }),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Source Selection Bottom Sheet ─────────────────────────────────────────

  void _showSourceSelectionSheet(Device destination) {
    String? pendingSourceId = _activeRoutes[destination.id];

    // Note: In sharing mode, we DON'T necessarily dispose background videos anymore,
    // as previews can share the SAME controller if already active!

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // Lazy-init previews specifically for this sheet session (staggered)
            Future.microtask(() async {
              for (final s in _sources) {
                if (s.videoUrl == null) continue;

                // If it's already in the main pool, it's already playing!
                if (_sourcePool.containsKey(s.id)) {
                  _sourcePreviewControllers[s.id] = _sourcePool[s.id]!;
                  setModalState(() {});
                  continue;
                }

                if (_sourcePreviewControllers[s.id] == null) {
                  final url = s.videoUrl!;
                  final ctrl = url.startsWith('http')
                      ? VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true))
                      : VideoPlayerController.asset(url, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
                  _sourcePreviewControllers[s.id] = ctrl;
                  try {
                    await ctrl.initialize().timeout(
                      const Duration(seconds: 10),
                    );
                    if (context.mounted) {
                      setModalState(() {});
                      await ctrl.setLooping(true);
                      await ctrl.setVolume(0);
                      await ctrl.play();
                    }
                  } catch (e) {
                    debugPrint('Preview video error (${s.name}): $e');
                  }
                  await Future.delayed(const Duration(milliseconds: 1000));
                }
              }
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade900),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Source',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentWhite,
                              ),
                            ),
                            Text(
                              'Routing to ${destination.name}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              mainAxisExtent: 140,
                            ),
                        itemCount: _sources.length,
                        itemBuilder: (context, i) {
                          final src = _sources[i];
                          final isSelected = pendingSourceId == src.id;

                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                pendingSourceId = src.id;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: AppTheme.highlightGrey,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? Colors.greenAccent
                                          : Colors.grey.shade800,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    (_sourcePreviewControllers[src.id] !=
                                                null &&
                                            _sourcePreviewControllers[src.id]!
                                                .value
                                                .isInitialized)
                                        ? FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            width:
                                                _sourcePreviewControllers[src
                                                        .id]!
                                                    .value
                                                    .size
                                                    .width,
                                            height:
                                                _sourcePreviewControllers[src
                                                        .id]!
                                                    .value
                                                    .size
                                                    .height,
                                            child: VideoPlayer(
                                              _sourcePreviewControllers[src
                                                  .id]!,
                                            ),
                                          ),
                                        )
                                        : Container(
                                          color: Colors.black,
                                          child: const Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.greenAccent,
                                              ),
                                            ),
                                          ),
                                        ),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.6),
                                            Colors.black.withValues(alpha: 0.4),
                                            Colors.black.withValues(alpha: 0.8),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Checkbox(
                                        value: isSelected,
                                        activeColor: Colors.greenAccent,
                                        checkColor: Colors.black,
                                        side: const BorderSide(
                                          color: Colors.white54,
                                          width: 1.5,
                                        ),
                                        onChanged: (val) {
                                          if (val == true) {
                                            setModalState(() {
                                              pendingSourceId = src.id;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Spacer(),
                                          Text(
                                            src.name,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            src.location,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade400,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade900),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            pendingSourceId != null
                                ? () {
                                  _changeRoute(
                                    destination.id,
                                    pendingSourceId!,
                                  );
                                  setState(() {
                                    _selectedDestinationId = null;
                                  });
                                  Navigator.pop(ctx);
                                }
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: Colors.grey.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Apply Source',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      // Reclaim memory for sheet-only previews, but DO NOT dispose if sharing with main pool
      for (final id in _sourcePreviewControllers.keys) {
        final ctrl = _sourcePreviewControllers[id];
        if (ctrl != null && !_sourcePool.containsValue(ctrl)) {
          ctrl
              .pause()
              .then((_) => ctrl.dispose())
              .catchError((_) => ctrl.dispose());
        }
      }
      _sourcePreviewControllers.clear();

      if (mounted) {
        _syncDestControllers();
        setState(() {});
      }
    });
  }

  // ── Provisioning Dialogs ──────────────────────────────────────────────────

  void _showAddDestinationDialog() {
    final nameCtrl = TextEditingController();
    final newLocCtrl = TextEditingController();
    final existingLocations = AppState.instance.destinationsByLocation.keys.toList();
    String? selectedLocation = existingLocations.isNotEmpty ? existingLocations.first : null;
    bool isCreatingNewLocation = existingLocations.isEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundLight,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade800)),
          title: const Row(
            children: [
              Icon(Icons.add_to_queue, color: AppTheme.accentWhite),
              SizedBox(width: 10),
              Text(
                'Provision Display',
                style: TextStyle(color: AppTheme.accentWhite, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    labelStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.monitor, color: Colors.grey),
                  ),
                ),
                if (existingLocations.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Container(height: 1, color: Colors.grey.shade800)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'LOCATION',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(child: Container(height: 1, color: Colors.grey.shade800)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else const SizedBox(height: 16),
                if (!isCreatingNewLocation && existingLocations.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedLocation,
                        dropdownColor: AppTheme.highlightGrey,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        items: existingLocations.map((loc) {
                          return DropdownMenuItem(
                            value: loc,
                            child: Text(loc, style: const TextStyle(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() => selectedLocation = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => isCreatingNewLocation = true),
                      icon: const Icon(Icons.add, size: 14, color: AppTheme.accentWhite),
                      label: const Text('Create New Location', style: TextStyle(color: AppTheme.accentWhite, fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: newLocCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'New Location Name',
                      labelStyle: TextStyle(color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.meeting_room, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (existingLocations.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => isCreatingNewLocation = false),
                        icon: const Icon(Icons.list, size: 14, color: Colors.grey),
                        label: Text('Select Existing', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentWhite,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                final loc = isCreatingNewLocation ? newLocCtrl.text.trim() : selectedLocation;
                if (nameCtrl.text.trim().isNotEmpty && loc != null && loc.isNotEmpty) {
                  final newDevice = Device(
                    id: 'dest_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    ip: '192.168.1.xxx', // Auto-generated/mocked
                    type: DeviceType.rx,
                    status: DeviceStatus.online,
                    location: loc,
                  );

                  if (!AppState.instance.destinationsByLocation.containsKey(loc)) {
                    AppState.instance.destinationsByLocation[loc] = [];
                    _expandedLocations[loc] = true;
                  }
                  AppState.instance.destinationsByLocation[loc]!.add(newDevice);
                  AppState.instance.notifyListeners();
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Provision', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }),
    );
  }
}
