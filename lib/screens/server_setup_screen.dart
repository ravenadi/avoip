import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../config/api_config.dart';
import '../services/controller_discovery.dart';
import 'sc1_ble_setup_screen.dart';

/// Shown right after login so the client can point the app at their AV
/// controller. Controllers announce themselves on the network, so they are
/// listed here to pick from; typing the IP is the fallback.
class ServerSetupScreen extends StatefulWidget {
  final bool isAdmin;
  const ServerSetupScreen({super.key, required this.isAdmin});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  late final TextEditingController _ipCtrl;
  String? _error;
  bool _searching = false;
  bool _choosePath = true;
  List<FoundController> _found = const [];

  static final _ipv4Re = RegExp(
    r'^(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(\.(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}$',
  );

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: ApiConfig.ip ?? '');
    _search();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _search({bool retryIfEmpty = true}) async {
    setState(() => _searching = true);
    final found = await ControllerDiscovery.find();
    if (!mounted) return;
    // The first search on iOS can come back empty while the "find devices
    // on your local network" permission prompt is still up, so try once more.
    if (found.isEmpty && retryIfEmpty) {
      return _search(retryIfEmpty: false);
    }
    setState(() {
      _searching = false;
      _found = found;
    });
  }

  Future<void> _connect(String ip, {String? hostname}) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final response = await http
          .get(Uri.parse('http://$ip:${ApiConfig.port}/health'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 ||
          (jsonDecode(response.body) as Map)['status'] != 'ok') {
        throw const FormatException('Controller health check failed');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error =
              'Could not confirm this controller. Check your network and try again.';
        });
      }
      return;
    }
    await ApiConfig.setIp(ip, hostname: hostname);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AppShell(isAdmin: widget.isAdmin),
        ),
      );
    }
  }

  Future<void> _continueWithTypedIp() async {
    final ip = _ipCtrl.text.trim();
    if (!_ipv4Re.hasMatch(ip)) {
      setState(() => _error = 'Enter a valid IP address, e.g. 192.168.22.11');
      return;
    }
    setState(() => _error = null);
    // Keep the hostname if this IP belongs to a controller on the list, or
    // is the one already saved, so a later IP change can still be followed.
    final listed = _found.where((c) => c.ip == ip).firstOrNull;
    final hostname =
        listed?.hostname ?? (ip == ApiConfig.ip ? ApiConfig.hostname : null);
    await _connect(ip, hostname: hostname);
  }

  @override
  Widget build(BuildContext context) {
    if (_choosePath) return _buildSetupPaths();
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.dns_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Connect to AV Controller',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pick the controller on this network, or enter its IP address.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 32),
                  _panel(child: _buildFoundList()),
                  const SizedBox(height: 16),
                  _panel(child: _buildManualEntry()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupPaths() {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const Icon(
                    Icons.settings_input_antenna,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Set up your SC-1',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Choose how your SC-1 connects to the network.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 28),
                  _setupChoice(
                    icon: Icons.bluetooth,
                    title: 'New SC-1',
                    subtitle: 'Set up Wi-Fi over Bluetooth',
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                    Sc1BleSetupScreen(isAdmin: widget.isAdmin),
                          ),
                        ),
                  ),
                  const SizedBox(height: 12),
                  _setupChoice(
                    icon: Icons.cable,
                    title: 'SC-1 cable connected to my network',
                    subtitle: 'Find it on the same Wi-Fi as this phone',
                    onTap: () => setState(() => _choosePath = false),
                  ),
                  const SizedBox(height: 12),
                  _setupChoice(
                    icon: Icons.wifi,
                    title: 'Dedicated AV Wi-Fi',
                    subtitle:
                        'Connect this phone to the AV Wi-Fi, then find the SC-1',
                    onTap:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (dialogContext) => AlertDialog(
                                title: const Text('Connect to the AV Wi-Fi'),
                                content: const Text(
                                  'Connect this phone to the dedicated AV Wi-Fi, then continue.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      setState(() => _choosePath = false);
                                    },
                                    child: const Text('Continue'),
                                  ),
                                ],
                              ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: AppTheme.highlightGrey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _buildFoundList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Controllers on this network',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_searching)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              IconButton(
                onPressed: () => _search(retryIfEmpty: false),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                tooltip: 'Search again',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_searching && _found.isEmpty)
          const Text('Searching...', style: TextStyle(color: Colors.grey))
        else if (_found.isEmpty)
          const Text(
            'No controller found. Make sure this phone is on the same Wi-Fi as your SC-1 controller, or enter its IP below.',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
        for (final controller in _found)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: AppTheme.highlightGrey,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap:
                    () =>
                        _connect(controller.ip, hostname: controller.hostname),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.router_outlined,
                        color: Colors.greenAccent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              controller.ip,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildManualEntry() {
    return Column(
      children: [
        TextField(
          controller: _ipCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Controller IP address',
            labelStyle: const TextStyle(color: Colors.grey),
            hintText: '192.168.22.11',
            hintStyle: TextStyle(color: Colors.grey.shade700),
            prefixIcon: const Icon(Icons.wifi_tethering, color: Colors.white54),
            border: InputBorder.none,
            errorText: _error,
          ),
          onSubmitted: (_) => _continueWithTypedIp(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _continueWithTypedIp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentWhite,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
