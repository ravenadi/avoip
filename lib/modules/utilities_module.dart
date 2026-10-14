import 'package:flutter/material.dart';

import '../logic/app_state.dart';
import '../models/device_model.dart';
import '../services/unit_status_service.dart';
import '../theme/app_theme.dart';

/// Live status of every box: is a monitor connected, is video coming in,
/// at what resolution and refresh rate, and which firmware it runs.
class UtilitiesModule extends StatefulWidget {
  const UtilitiesModule({super.key});

  @override
  State<UtilitiesModule> createState() => _UtilitiesModuleState();
}

class _UtilitiesModuleState extends State<UtilitiesModule> {
  List<UnitStatus> _units = const [];
  ControllerApiException? _error;
  bool _loading = false;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    AppState.instance.currentTab.addListener(_onTabChanged);
    if (AppState.instance.currentTab.value == AppTabs.utilities) _load();
  }

  @override
  void dispose() {
    AppState.instance.currentTab.removeListener(_onTabChanged);
    super.dispose();
  }

  // Reading every box takes a few seconds, so only load when shown.
  void _onTabChanged() {
    if (AppState.instance.currentTab.value == AppTabs.utilities) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await AppState.instance.refreshDevices(minInterval: Duration.zero);
      final units = await UnitStatusService.fetchAll();
      if (!mounted) return;
      setState(() {
        _units = units;
        _error = null;
        _updatedAt = DateTime.now();
      });
    } on ControllerApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _nameOf(UnitStatus unit) {
    final state = AppState.instance;
    for (final d in [
      ...state.sources,
      ...state.destinationsByLocation.values.expand((d) => d),
    ]) {
      if (d.controllerId == unit.id) return d.name;
    }
    return state.controllerDeviceNames[unit.id] ?? unit.ip;
  }

  Device? _deviceOf(UnitStatus unit) {
    final state = AppState.instance;
    for (final d in [
      ...state.sources,
      ...state.destinationsByLocation.values.expand((d) => d),
    ]) {
      if (d.controllerId == unit.id) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Utilities',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accentWhite,
                      ),
                    ),
                  )
                else
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white70,
                    ),
                    tooltip: 'Refresh',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _updatedAt == null
                  ? 'Live status read from each box.'
                  : 'Live status read from each box. Updated '
                      '${_updatedAt!.hour.toString().padLeft(2, '0')}:'
                      '${_updatedAt!.minute.toString().padLeft(2, '0')}:'
                      '${_updatedAt!.second.toString().padLeft(2, '0')}.',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),
            _buildBody(isMobile ? 12.0 : 16.0),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(double spacing) {
    if (_loading && _units.isEmpty) {
      return _message(
        null,
        'Reading the boxes...',
        'This takes a few seconds.',
      );
    }
    final error = _error;
    if (error != null) {
      return _message(
        error.unsupported
            ? Icons.system_update_alt_rounded
            : Icons.cloud_off_rounded,
        error.unsupported ? 'Controller update needed' : "Couldn't load status",
        error.message,
        onRetry: _load,
      );
    }
    if (_units.isEmpty) {
      return _message(
        Icons.devices_other_rounded,
        'No boxes yet',
        'Boxes the controller finds appear here.',
      );
    }

    final sources = _units.where((u) => u.isTx).toList();
    final screens = _units.where((u) => !u.isTx).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 420).ceil().clamp(1, 3);
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        Widget group(String title, List<UnitStatus> units) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final unit in units)
                  SizedBox(width: width, child: _buildCard(unit)),
              ],
            ),
            const SizedBox(height: 24),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sources.isNotEmpty) group('SOURCES (TX)', sources),
            if (screens.isNotEmpty) group('SCREENS (RX)', screens),
          ],
        );
      },
    );
  }

  Widget _message(
    IconData? icon,
    String title,
    String detail, {
    VoidCallback? onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            if (icon != null)
              Icon(icon, size: 48, color: Colors.grey.shade700)
            else
              const CircularProgressIndicator(color: AppTheme.accentWhite),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  static String? _video(String? resolution, num? hz) {
    if (resolution == null) return null;
    return hz == null ? resolution : '$resolution @ ${_hz(hz)} Hz';
  }

  static String _hz(num hz) =>
      hz == hz.roundToDouble() ? hz.round().toString() : hz.toStringAsFixed(2);

  Widget _buildCard(UnitStatus unit) {
    final reachable = unit.reachable;
    final firmware =
        unit.firmwareVersion == null
            ? null
            : unit.firmwareBuild == null
            ? unit.firmwareVersion
            : '${unit.firmwareVersion} (build ${unit.firmwareBuild})';

    final rows = <Widget>[
      if (unit.isTx) ...[
        if (_deviceOf(unit)?.channel case final channel?)
          _row('Channel', channel),
        _flagRow('Video in', unit.videoDetected, 'Detected', 'No video'),
        _row('Input', _video(unit.sourceResolution, unit.sourceRefreshHz)),
        _row('Signal', unit.signalType),
      ] else ...[
        if (_deviceOf(unit)?.currentTxIp case final txIp?)
          _row('Showing', 'TX $txIp'),
        _flagRow(
          'Monitor',
          unit.monitorConnected,
          'Connected',
          'Not connected',
        ),
        _flagRow('Video', unit.videoDetected, 'Receiving', 'No video'),
        _row('Source', _video(unit.sourceResolution, unit.sourceRefreshHz)),
        _row('Output', _video(unit.outputResolution, unit.outputRefreshHz)),
      ],
      _row('Firmware', firmware),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              reachable
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.redAccent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                unit.isTx ? Icons.play_arrow_rounded : Icons.monitor,
                color: unit.isTx ? Colors.purpleAccent : Colors.blueAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nameOf(unit),
                      style: const TextStyle(
                        color: AppTheme.accentWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      unit.ip,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _chip(
                reachable ? 'ONLINE' : 'NOT RESPONDING',
                reachable ? Colors.greenAccent : Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // A box that doesn't answer has no live values to show.
          Opacity(opacity: reachable ? 1 : 0.4, child: Column(children: rows)),
        ],
      ),
    );
  }

  Widget _row(String label, String? value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '—',
              style: TextStyle(color: color ?? Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // A yes/no reading; "no" is a warning worth noticing.
  Widget _flagRow(String label, bool? value, String yes, String no) {
    return _row(
      label,
      value == null ? null : (value ? yes : no),
      color:
          value == null
              ? null
              : (value ? Colors.greenAccent : Colors.orangeAccent),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
}
