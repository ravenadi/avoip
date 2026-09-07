import 'package:flutter/material.dart';
import 'dart:math';
import '../theme/app_theme.dart';
import '../logic/app_state.dart';
import '../models/device_model.dart';
import '../services/device_api_service.dart';
import '../services/database_service.dart';

// Using global DeviceType from models/device_model.dart
enum AdoptStatus { pending, adopting, adopted }

class DiscoveredDevice {
  final String name;
  final String ip;
  final String mac;
  final int signal;
  final DeviceType type;
  AdoptStatus status;

  DiscoveredDevice({
    required this.name,
    required this.ip,
    required this.mac,
    required this.signal,
    required this.type,
    this.status = AdoptStatus.pending,
  });
}

class DiscoveryModule extends StatefulWidget {
  const DiscoveryModule({super.key});
  @override
  State<DiscoveryModule> createState() => _DiscoveryModuleState();
}

class _DiscoveryModuleState extends State<DiscoveryModule>
    with TickerProviderStateMixin {
  bool _isScanning = false;
  String _scanStatus = '';
  String _filterType = 'All';
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  final List<DiscoveredDevice> _devices = [];

  List<DiscoveredDevice> get _filteredDevices {
    if (_filterType == 'RX') return _devices.where((d) => d.type == DeviceType.rx).toList();
    if (_filterType == 'TX') return _devices.where((d) => d.type == DeviceType.tx).toList();
    if (_filterType == 'CX') return _devices.where((d) => d.type == DeviceType.cx).toList();
    return _devices;
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _loadFromDatabase();
  }

  // ── Load last scan results from DB on app open ─────────────────────────────
  Future<void> _loadFromDatabase() async {
    final rows = await DatabaseService.instance.loadDiscoveredDevices();
    if (!mounted || rows.isEmpty) return;

    // Build set of already-adopted device IDs (mac-based)
    final adoptedIds = {
      ...AppState.instance.sources.map((d) => d.id),
      ...AppState.instance.destinationsByLocation.values.expand((d) => d).map((d) => d.id),
    };

    setState(() {
      for (final row in rows) {
        final ip = row['ip'] as String;
        if (_devices.any((d) => d.ip == ip)) continue;
        final mac = row['mac'] as String;
        final deviceId = mac.replaceAll(':', '');
        _devices.add(DiscoveredDevice(
          name: row['name'] as String,
          ip: ip,
          mac: mac,
          signal: (row['signal'] as int?) ?? 100,
          type: DeviceType.values.firstWhere(
            (e) => e.name == (row['type'] as String),
            orElse: () => DeviceType.rx,
          ),
          status: adoptedIds.contains(deviceId) ? AdoptStatus.adopted : AdoptStatus.pending,
        ));
      }
    });
  }

  // ── Mark already-adopted devices after every scan ─────────────────────────
  void _restoreAdoptedStatus() {
    final adoptedIds = {
      ...AppState.instance.sources.map((d) => d.id),
      ...AppState.instance.destinationsByLocation.values.expand((d) => d).map((d) => d.id),
    };
    for (final device in _devices) {
      final deviceId = device.mac.replaceAll(':', '');
      if (adoptedIds.contains(deviceId)) {
        device.status = AdoptStatus.adopted;
      }
    }
  }

  // ── Save scan results to DB after every scan ───────────────────────────────
  Future<void> _saveToDatabase(List<DiscoveredDevice> devices) async {
    final maps = devices.map((d) => {
      'name': d.name,
      'ip': d.ip,
      'mac': d.mac,
      'signal': d.signal,
      'type': d.type.name,
    }).toList();
    await DatabaseService.instance.saveDiscoveredDevices(maps);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startScan() async {
    setState(() {
      _isScanning = true;
      _scanStatus = 'Detecting network...';
      _devices.clear();
    });

    final found = await DeviceApiService.fetchDevices(
      onStatus: (status) {
        if (mounted) setState(() => _scanStatus = status);
      },
    );

    if (!mounted) return;

    final previousCount = _devices.length;
    setState(() {
      _isScanning = false;
      _scanStatus = '';
      for (final device in found) {
        if (!_devices.any((d) => d.ip == device.ip)) {
          _devices.add(device);
        }
      }
      _restoreAdoptedStatus();
    });

    if (found.isNotEmpty) await _saveToDatabase(found);
    if (mounted) _showScanResultPopup(found, previousCount);
  }

  void _showScanResultPopup(List<DiscoveredDevice> found, int previousCount) {
    final newDevices = found.where((d) {
      final id = d.mac.replaceAll(':', '');
      final adoptedIds = {
        ...AppState.instance.sources.map((s) => s.id),
        ...AppState.instance.destinationsByLocation.values.expand((l) => l).map((s) => s.id),
      };
      return !adoptedIds.contains(id);
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            // Result icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: found.isEmpty ? Colors.orange.withValues(alpha: 0.1) : Colors.greenAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                found.isEmpty ? Icons.wifi_off_rounded : Icons.radar_rounded,
                color: found.isEmpty ? Colors.orangeAccent : Colors.greenAccent,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              found.isEmpty ? 'No Devices Found' : 'Scan Complete',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            if (found.isEmpty)
              Text(
                'Make sure your phone is on the\nsame WiFi as your AV devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _resultChip('${found.length} Total', Colors.blue),
                  const SizedBox(width: 8),
                  _resultChip('${newDevices.length} New', Colors.greenAccent),
                  const SizedBox(width: 8),
                  _resultChip('${found.length - newDevices.length} Adopted', Colors.purple),
                ],
              ),
              if (newDevices.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('New Devices Found', style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                ...newDevices.take(3).map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(d.type == DeviceType.tx ? Icons.cast_rounded : Icons.monitor_rounded,
                          size: 16, color: d.type == DeviceType.tx ? Colors.purpleAccent : Colors.blueAccent),
                      const SizedBox(width: 10),
                      Text(d.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      const Spacer(),
                      Text(d.ip, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    ],
                  ),
                )),
                if (newDevices.length > 3)
                  Text('+${newDevices.length - 3} more', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _resultChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Future<void> _adoptDevice(DiscoveredDevice dev) async {
    setState(() => dev.status = AdoptStatus.adopting);
    
    // Simulate adoption handshake delay
    await Future.delayed(const Duration(seconds: 1));
    
    if (mounted) {
      // Execute the registry adoption in AppState
      await AppState.instance.adoptDevice(
        dev.mac.replaceAll(':', ''),
        dev.name,
        dev.ip,
        dev.type,
      );

      setState(() => dev.status = AdoptStatus.adopted);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${dev.name} Adopted! Opening Hardware Config...'),
          backgroundColor: Colors.greenAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Wait for snackbar to be seen
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (mounted) {
        // Tab index 3 is Configuration
        AppState.instance.tabIndexNotifier.value = 3;
      }
    }
  }

  Color _signalColor(int signal) {
    if (signal >= 75) return Colors.greenAccent;
    if (signal >= 45) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  IconData _typeIcon(DeviceType type) {
    switch (type) {
      case DeviceType.rx: return Icons.monitor_rounded;
      case DeviceType.tx: return Icons.cast_rounded;
      case DeviceType.cx: return Icons.hub_rounded;
      default: return Icons.device_unknown_rounded;
    }
  }

  String _typeLabel(DeviceType type) {
    switch (type) {
      case DeviceType.rx: return 'RX';
      case DeviceType.tx: return 'TX';
      case DeviceType.cx: return 'CX';
      default: return '?';
    }
  }

  Color _typeColor(DeviceType type) {
    switch (type) {
      case DeviceType.rx: return Colors.blueAccent;
      case DeviceType.tx: return Colors.purpleAccent;
      case DeviceType.cx: return Colors.orangeAccent;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _devices.length;
    final adopted = _devices.where((d) => d.status == AdoptStatus.adopted).length;
    final pending = total - adopted;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Device Discovery',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                    const SizedBox(height: 4),
                    Text('Scan the network for AVoIP hardware',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ),
              _buildScanButton(),
            ],
          ),
          const SizedBox(height: 16),

          // ── WiFi Notice Banner ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_rounded, color: Colors.blueAccent, size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect to the AV System WiFi',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Make sure your phone is connected to the same WiFi network as the Netgear box before scanning.',
                        style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 11, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Stats Row ───────────────────────────────────────────────────────
          Row(
            children: [
              _statTile(Icons.devices_rounded, total.toString(), 'Found', Colors.blue.shade300),
              const SizedBox(width: 10),
              _statTile(Icons.check_circle_rounded, adopted.toString(), 'Adopted', Colors.greenAccent),
              const SizedBox(width: 10),
              _statTile(Icons.pending_rounded, pending.toString(), 'Pending', Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 20),

          // ── Radar Animation + Progress (when scanning) ──────────────────────
          if (_isScanning) _buildRadar(),
          if (_isScanning) const SizedBox(height: 12),
          if (_isScanning) Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: null, // indeterminate — scanning all IPs at once
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade800,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _scanStatus.isEmpty ? 'Scanning network...' : _scanStatus,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            ],
          ),
          if (_isScanning) const SizedBox(height: 20),

          // ── Filter Chips ─────────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'RX', 'TX', 'CX'].map((f) {
                final selected = _filterType == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterType = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? Colors.greenAccent : Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? Colors.greenAccent : Colors.grey.shade800),
                      ),
                      child: Text(f,
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.grey.shade400,
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // ── Device List / Empty State ─────────────────────────────────────────
          if (_filteredDevices.isEmpty && !_isScanning)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.wifi_find_rounded, size: 40, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Text('No Devices Found',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Make sure your phone is on the\nsame WiFi as your AV devices.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _startScan,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.radar_rounded, color: Colors.greenAccent, size: 16),
                            SizedBox(width: 8),
                            Text('Try Again', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_filteredDevices.length, (i) => _buildDeviceCard(_filteredDevices[i])),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    return GestureDetector(
      onTap: _isScanning ? null : _startScan,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: _isScanning ? Colors.grey.shade800 : Colors.greenAccent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isScanning ? [] : [
            BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isScanning)
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.radar_rounded, size: 16, color: Colors.black),
            const SizedBox(width: 8),
            Text(
              _isScanning ? 'Scanning...' : 'Start Scan',
              style: TextStyle(
                color: _isScanning ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade800),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildRadar() {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          return SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(
              painter: _RadarPainter(_pulseAnim.value),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(DiscoveredDevice dev) {
    final isAdopted = dev.status == AdoptStatus.adopted;
    final isAdopting = dev.status == AdoptStatus.adopting;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAdopted ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.grey.shade800,
          width: isAdopted ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Type badge icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _typeColor(dev.type).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_typeIcon(dev.type), color: _typeColor(dev.type), size: 22),
                ),
                const SizedBox(width: 14),
                // Name and IP
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              dev.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _typeColor(dev.type).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(_typeLabel(dev.type),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _typeColor(dev.type))),
                          ),
                          if (isAdopted) ...[ 
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle_rounded, size: 14, color: Colors.greenAccent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(dev.ip, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                          if (dev.type == DeviceType.cx) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
                              ),
                              child: const Text('AUTO-IP DISCOVERED', style: TextStyle(color: Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Signal strength
                Column(
                  children: [
                    Text('${dev.signal}%',
                        style: TextStyle(color: _signalColor(dev.signal), fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Icon(Icons.signal_wifi_4_bar_rounded, size: 14, color: _signalColor(dev.signal)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // MAC + Divider
            Row(
              children: [
                Icon(Icons.memory_rounded, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text('MAC: ${dev.mac}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                const Spacer(),
                // Signal bar mini
                _SignalBars(signal: dev.signal),
              ],
            ),
            const SizedBox(height: 12),
            // Signal progress + Adopt button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Signal Strength', style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: dev.signal / 100,
                          minHeight: 5,
                          backgroundColor: Colors.grey.shade800,
                          valueColor: AlwaysStoppedAnimation<Color>(_signalColor(dev.signal)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 36,
                  child: isAdopted
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                          ),
                          alignment: Alignment.center,
                          child: const Text('Adopted ✓',
                              style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        )
                      : ElevatedButton(
                          onPressed: isAdopting ? null : () => _adoptDevice(dev),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.grey.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: isAdopting
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Text('Adopt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  final int signal;
  const _SignalBars({required this.signal});
  @override
  Widget build(BuildContext context) {
    Color color = signal >= 75 ? Colors.greenAccent : (signal >= 45 ? Colors.orangeAccent : Colors.redAccent);
    return Row(
      children: List.generate(4, (i) {
        final active = signal >= (i + 1) * 25;
        return Container(
          margin: const EdgeInsets.only(left: 2),
          width: 4,
          height: 6.0 + i * 3,
          decoration: BoxDecoration(
            color: active ? color : Colors.grey.shade800,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Background circles
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(
        center,
        maxR * i / 3,
        Paint()
          ..color = Colors.greenAccent.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Sweeping arc
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [Colors.transparent, Colors.greenAccent.withValues(alpha: 0.4)],
        startAngle: -pi / 2,
        endAngle: -pi / 2 + 2 * pi * progress,
      ).createShader(Rect.fromCircle(center: center, radius: maxR))
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR),
      -pi / 2,
      2 * pi * progress,
      true,
      sweepPaint,
    );

    // Center dot
    canvas.drawCircle(center, 4, Paint()..color = Colors.greenAccent);

    // Pulsing dot at edge of sweep
    final angle = -pi / 2 + 2 * pi * progress;
    final dotPos = Offset(center.dx + maxR * cos(angle), center.dy + maxR * sin(angle));
    canvas.drawCircle(dotPos, 4, Paint()..color = Colors.greenAccent.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
