import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../config/api_config.dart';

/// Shown right after login so the client can point the app at their
/// AV control server. The IP entered here is used to build every
/// backend API URL (device scan, routing commands, stop).
class ServerSetupScreen extends StatefulWidget {
  final bool isAdmin;
  const ServerSetupScreen({super.key, required this.isAdmin});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  late final TextEditingController _ipCtrl;
  String? _error;

  static final _ipv4Re = RegExp(
    r'^(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})(\.(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})){3}$',
  );

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: ApiConfig.ip ?? '');
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final ip = _ipCtrl.text.trim();
    if (!_ipv4Re.hasMatch(ip)) {
      setState(() => _error = 'Enter a valid IP address, e.g. 192.168.22.11');
      return;
    }
    setState(() => _error = null);

    await ApiConfig.setIp(ip);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => AppShell(isAdmin: widget.isAdmin)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.dns_outlined, color: Colors.white70, size: 48),
                const SizedBox(height: 24),
                Text(
                  'Connect to AV Server',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the IP address of the AV control server\non this network to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 40),
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _ipCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Server IP Address',
                          labelStyle: const TextStyle(color: Colors.grey),
                          hintText: '192.168.22.11',
                          hintStyle: TextStyle(color: Colors.grey.shade700),
                          prefixIcon: const Icon(Icons.wifi_tethering, color: Colors.white54),
                          border: InputBorder.none,
                          errorText: _error,
                        ),
                        onSubmitted: (_) => _continue(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _continue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentWhite,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
    );
  }
}
