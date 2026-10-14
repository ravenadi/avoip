import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../logic/app_state.dart';
import '../models/device_model.dart';
import '../services/database_service.dart';

class ConfigurationModule extends StatefulWidget {
  const ConfigurationModule({super.key});

  @override
  State<ConfigurationModule> createState() => _ConfigurationModuleState();
}

class _ConfigurationModuleState extends State<ConfigurationModule> {
  @override
  void initState() {
    super.initState();
    // Use postFrameCallback to ensure the dialog triggers AFTER the first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNewAdoption();
    });
    // Listen for tab changes as well
    AppState.instance.currentTab.addListener(_checkNewAdoption);
  }

  @override
  void dispose() {
    AppState.instance.currentTab.removeListener(_checkNewAdoption);
    super.dispose();
  }

  void _checkNewAdoption() {
    // Only proceed if the configuration tab is now active
    if (AppState.instance.currentTab.value != AppTabs.configuration) return;

    final newId = AppState.instance.lastAdoptedDeviceId;
    if (newId != null) {
      // Use postFrame to ensure any existing build cycle is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final device = _allDevices.firstWhere((d) => d.id == newId);
          _showEditDeviceDialog(device);
        } catch (e) {
          debugPrint('Auto-focus failed: Device $newId not found in registry');
        }
        AppState.instance.lastAdoptedDeviceId = null;
      });
    }
  }

  // Deep extraction of global devices
  List<Device> get _allDevices {
    final List<Device> all = [];
    all.addAll(AppState.instance.sources);
    for (var list in AppState.instance.destinationsByLocation.values) {
      all.addAll(list);
    }
    // Sort generically
    all.sort((a, b) => a.name.compareTo(b.name));
    return all;
  }

  void _showEditDeviceDialog(Device device) {
    final nameCtrl = TextEditingController(text: device.name);
    final locCtrl = TextEditingController(text: device.location);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        children: [
                          Icon(
                            device.type == DeviceType.tx
                                ? Icons.play_arrow_rounded
                                : Icons.monitor,
                            color: AppTheme.accentWhite,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Hardware Configuration',
                            style: const TextStyle(
                              color: AppTheme.accentWhite,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Modify parameters for ${device.name}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Divider(color: Colors.white12, height: 24),
                          TextField(
                            controller: nameCtrl,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Alias Name',
                              labelStyle: const TextStyle(color: Colors.grey),
                              prefixIcon: const Icon(
                                Icons.abc,
                                color: Colors.white38,
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: locCtrl,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Deployment Zone',
                              labelStyle: const TextStyle(color: Colors.grey),
                              prefixIcon: const Icon(
                                Icons.place_outlined,
                                color: Colors.white38,
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await AppState.instance.removeDevice(
                                  device.id,
                                  device.location,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${device.name} Decoupled'),
                                      backgroundColor: Colors.redAccent,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'DECOMMISSION',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text(
                                'CANCEL',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentWhite,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                final oldLocation = device.location;
                                final newName =
                                    nameCtrl.text.isNotEmpty
                                        ? nameCtrl.text
                                        : device.name;
                                final newLocation =
                                    locCtrl.text.isNotEmpty
                                        ? locCtrl.text
                                        : device.location;

                                device.name = newName;

                                // If location changed, move device to new location group
                                if (newLocation != oldLocation &&
                                    device.type != DeviceType.tx) {
                                  AppState
                                      .instance
                                      .destinationsByLocation[oldLocation]
                                      ?.remove(device);
                                  if (AppState
                                          .instance
                                          .destinationsByLocation[oldLocation]
                                          ?.isEmpty ??
                                      false) {
                                    AppState.instance.destinationsByLocation
                                        .remove(oldLocation);
                                  }
                                  AppState.instance.destinationsByLocation
                                      .putIfAbsent(newLocation, () => []);
                                  AppState
                                      .instance
                                      .destinationsByLocation[newLocation]!
                                      .add(device);
                                }
                                device.location = newLocation;

                                // Persist to DB
                                await DatabaseService.instance
                                    .saveAdoptedDevice(device);
                                if (ctx.mounted) {
                                  AppState.instance.notifyListeners();
                                  Navigator.pop(ctx);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${device.name} Configured',
                                      ),
                                      backgroundColor: Colors.greenAccent,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'SAVE',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ).whenComplete(() {
      nameCtrl.dispose();
      locCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppState.instance.stateVersionNotifier,
      builder: (context, _, child) {
        // PROACTIVE ADOPTION CHECK:
        // Every time the global state changes, check if we need to show the naming menu.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _checkNewAdoption(),
        );

        final devices = _allDevices;
        final isMobile = MediaQuery.of(context).size.width < 700;
        final spacing = isMobile ? 12.0 : 20.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Configuration',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set an app-only display name and location. Device IPs are managed automatically.',
                style: TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 24),
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'No devices yet.\nDevices adopted in Discovery appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              // Cards size to their content, so long names can wrap.
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 500).ceil().clamp(
                    1,
                    4,
                  );
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final dev in devices)
                        SizedBox(width: width, child: _buildDeviceCard(dev)),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeviceCard(Device dev) {
    final isTx = dev.type == DeviceType.tx;
    final isOnline = dev.status == DeviceStatus.online;
    final typeColor = isTx ? Colors.purpleAccent : Colors.blueAccent;
    final statusColor = isOnline ? Colors.greenAccent : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isOnline ? Colors.white.withValues(alpha: 0.1) : Colors.redAccent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDeviceIcon(dev),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dev.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.accentWhite,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _tag(isTx ? 'TX' : 'RX', typeColor),
                    if (isTx && dev.channel != null)
                      _tag('Ch ${dev.channel}', Colors.orangeAccent),
                    _tag(isOnline ? 'ONLINE' : 'OFFLINE', statusColor),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.lan_outlined,
                      size: 12,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        dev.ip,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          fontFamily: 'monospace',
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
          const SizedBox(width: 8),
          _miniActionButton(
            icon: Icons.tune_rounded,
            tooltip: 'Configure',
            onTap: () => _showEditDeviceDialog(dev),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDeviceIcon(Device dev) {
    final isTx = dev.type == DeviceType.tx;
    final isOnline = dev.status == DeviceStatus.online;

    return Stack(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.backgroundLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          // A play button for sources, a screen for displays.
          child: Icon(
            isTx ? Icons.play_arrow_rounded : Icons.monitor,
            color: isTx ? Colors.purpleAccent : Colors.blueAccent,
            size: isTx ? 30 : 24,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isOnline ? Colors.greenAccent : Colors.redAccent,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.highlightGrey, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, size: 14, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
