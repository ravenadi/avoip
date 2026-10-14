import 'package:flutter/material.dart';
import '../logic/app_state.dart';
import '../models/device_model.dart';
import '../widgets/device_preview.dart';

/// Full-screen live view of one device's controller stream. Leaving the
/// screen disposes the stream, which frees the controller's stream slot.
class LiveViewScreen extends StatelessWidget {
  final Device device;
  const LiveViewScreen({super.key, required this.device});

  /// Opens the live view, if the controller has given this device any URLs.
  static void open(BuildContext context, Device device) {
    if (device.streamUrl == null && device.previewUrl == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LiveViewScreen(device: device)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          device.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        // URLs change when the controller restarts; rebuild with new ones.
        child: ValueListenableBuilder<int>(
          valueListenable: AppState.instance.stateVersionNotifier,
          builder: (context, _, _) {
            final streamUrl = device.streamUrl;
            final previewUrl = device.previewUrl;
            if (streamUrl != null) {
              return MjpegStreamView(
                streamUrl: streamUrl,
                previewUrl: previewUrl,
              );
            }
            if (previewUrl != null) {
              return PolledPreview(url: previewUrl, fit: BoxFit.contain);
            }
            return const PreviewUnavailable(
              detail: 'The controller has no preview for this device.',
            );
          },
        ),
      ),
    );
  }
}
