import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../config/api_config.dart';
import '../services/controller_discovery.dart';
import '../services/sc1_ble_setup.dart';
import '../widgets/app_shell.dart';

/// End-to-end Bluetooth provisioning UI for the SC-1.
class Sc1BleSetupScreen extends StatefulWidget {
  final bool isAdmin;
  const Sc1BleSetupScreen({super.key, required this.isAdmin});

  @override
  State<Sc1BleSetupScreen> createState() => _Sc1BleSetupScreenState();
}

class _Sc1BleSetupScreenState extends State<Sc1BleSetupScreen>
    with WidgetsBindingObserver {
  final _ble = Sc1BleSetup();
  final _password = TextEditingController();
  final _ssid = TextEditingController();
  List<ScanResult> _devices = [];
  List<Sc1WifiNetwork> _networks = [];
  ScanResult? _selectedDevice;
  Sc1WifiNetwork? _selectedNetwork;
  Sc1WifiStatus? _lastStatus;
  bool _busy = false,
      _scanning = false,
      _showPassword = false,
      _otherNetwork = false;
  bool _handlingConnected = false;
  bool _credentialsSent = false;
  String? _requestedSsid;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ble.statuses.listen((status) {
      if (!mounted) return;
      setState(() => _lastStatus = status);
      if (_credentialsSent &&
          status.state == 'connected' &&
          _isRequestedNetwork(status))
        _handleConnected(status);
      if (_credentialsSent && status.state == 'failed') {
        _credentialsSent = false;
        setState(() {
          _busy = false;
          _error = _friendlyError(status.error);
        });
      }
      if (status.state == 'disconnected' && _busy && !_handlingConnected)
        _recoverStatus();
    });
    _scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _ssid.dispose();
    _ble.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _busy) _recoverStatus();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      await _ble.scan();
      if (mounted) setState(() => _devices = _ble.devices);
    } catch (e) {
      if (mounted)
        setState(
          () =>
              _error =
                  'Bluetooth scan failed. Check Bluetooth and permissions, then try again.',
        );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(ScanResult result) async {
    setState(() {
      _busy = true;
      _error = null;
      _selectedDevice = result;
      _handlingConnected = false;
    });
    try {
      await _ble.connect(result);
      final configured = _ble.info?['configured'] == true;
      if (configured && mounted) {
        final name = _ble.info?['wifi_ssid'] ?? 'Wi-Fi';
        final ip = _ble.info?['ip'];
        final useIt = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (c) => AlertDialog(
                title: Text('Already on $name'),
                content: Text(
                  'This SC-1 is already on Wi-Fi $name${ip == null ? '' : ' ($ip)'}. Use it or change Wi-Fi?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Change Wi-Fi'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Use it'),
                  ),
                ],
              ),
        );
        if (useIt == true) {
          final ssid = name.toString();
          _handlingConnected = true;
          await _ble.disconnect();
          await _findController(fallbackIp: ip?.toString(), ssid: ssid);
          return;
        }
        if (useIt == null) return;
      }
      if (!_ble.supportsContractVersion) {
        await _ble.disconnect();
        if (mounted)
          setState(() {
            _busy = false;
            _error =
                'This SC-1 uses a newer setup protocol. Update the app before configuring it.';
          });
        return;
      }
      if (_ble.info?['code_required'] == true) {
        final verified = await _verifySetupCode();
        if (!verified) return;
      }
      await _ble.subscribeStatus();
      await _loadNetworks();
    } catch (e) {
      if (mounted)
        setState(
          () =>
              _error =
                  'Could not connect to this SC-1. Move closer and try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForSetupCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Enter SC-1 setup code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter the code printed on the SC-1 sticker.'),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Setup code'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(dialogContext, controller.text.trim()),
                child: const Text('Verify'),
              ),
            ],
          ),
    );
    controller.dispose();
    return code?.isEmpty == true ? null : code;
  }

  Future<bool> _verifySetupCode() async {
    final code = await _askForSetupCode();
    if (code == null) return false;
    if (mounted)
      setState(() {
        _busy = true;
        _error = null;
      });
    try {
      await _ble.writeSetupCode(code);
      return true;
    } on Sc1BleWriteException catch (error) {
      if (mounted) setState(() => _error = _writeError(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _writeError(Sc1BleWriteException error) {
    if (error.status?.state == 'connecting')
      return 'A Wi-Fi connection is already running. Waiting for its result…';
    if (error.status?.state == 'failed')
      return _friendlyError(error.status?.error);
    return switch (error.code) {
      0x08 =>
        'Setup code was missing or incorrect. Check the sticker and try again. Five wrong codes lock setup for 5 minutes.',
      0x03 =>
        'Setup is temporarily locked after too many incorrect codes. Wait 5 minutes, then reconnect.',
      0xFE => 'A Wi-Fi connection is already running. Waiting for its result…',
      0x80 =>
        'The setup details were not accepted. Check the network name and try again.',
      0x0D => 'The network name or password is too long.',
      _ => 'Could not send Wi-Fi details. Check the setup code and try again.',
    };
  }

  Future<void> _loadNetworks() async {
    setState(() {
      _busy = true;
      _error = null;
      _selectedNetwork = null;
      _otherNetwork = false;
      _ssid.clear();
    });
    try {
      final found = await _ble.readNetworks();
      if (mounted) setState(() => _networks = found);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error =
                  'Could not scan for Wi-Fi networks. Refresh to try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _provision() async {
    final ssid =
        _otherNetwork ? _ssid.text.trim() : (_selectedNetwork?.ssid ?? '');
    if (!_otherNetwork && _selectedNetwork == null) {
      setState(() => _error = 'Tap a Wi-Fi network to select it first.');
      return;
    }
    if (ssid.isEmpty) {
      setState(() => _error = 'Enter a Wi-Fi network name.');
      return;
    }
    if (utf8.encode(ssid).length > 32) {
      setState(() => _error = 'Network names must be 32 bytes or fewer.');
      return;
    }
    if (_password.text.length > 64) {
      setState(
        () => _error = 'Wi-Fi passwords must be 64 characters or fewer.',
      );
      return;
    }
    if (_selectedNetwork?.secure == true && _password.text.isEmpty) {
      setState(() => _error = 'Enter the Wi-Fi password.');
      return;
    }
    if (_selectedNetwork?.secure == false) {
      final accepted = await showDialog<bool>(
        context: context,
        builder:
            (c) => AlertDialog(
              title: const Text('Open Wi-Fi network'),
              content: const Text(
                'This network does not use a password. Continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
      );
      if (accepted != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _lastStatus = null;
    });
    final password = _password.text;
    try {
      _requestedSsid = ssid;
      _credentialsSent = true;
      await _ble.provision(ssid, password);
    } on Sc1BleWriteException catch (error) {
      final alreadyRunning = error.status?.state == 'connecting';
      if (mounted)
        setState(() {
          _busy = alreadyRunning;
          _error = alreadyRunning ? null : _writeError(error);
        });
      if (alreadyRunning) {
        _credentialsSent = true;
        unawaited(_watchStatus());
      } else {
        _credentialsSent = false;
      }
      return;
    } catch (_) {
      _credentialsSent = false;
      if (mounted)
        setState(() {
          _busy = false;
          _error = 'Could not send Wi-Fi details. Reconnect and try again.';
        });
      return;
    } finally {
      _password.clear();
    }
    unawaited(_watchStatus());
  }

  Future<void> _watchStatus() async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (mounted && _busy && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !_busy) return;
      try {
        final status = await _ble.readStatus();
        if (!mounted) return;
        setState(() => _lastStatus = status);
        if (status.state == 'connected' && _isRequestedNetwork(status)) {
          await _handleConnected(status);
          return;
        }
        if (status.state == 'failed') {
          setState(() {
            _busy = false;
            _error = _friendlyError(status.error);
          });
          return;
        }
      } catch (_) {
        /* Notification and next poll may still recover. */
      }
    }
    if (mounted && _busy)
      setState(() {
        _busy = false;
        _error = _friendlyError('timeout');
      });
  }

  Future<void> _handleConnected(Sc1WifiStatus status) async {
    if (_handlingConnected) return;
    _handlingConnected = true;
    _credentialsSent = false;
    await _ble.disconnect();
    if (mounted)
      await _findController(fallbackIp: status.ip, ssid: status.ssid);
  }

  bool _isRequestedNetwork(Sc1WifiStatus status) =>
      status.ssid != null && status.ssid == _requestedSsid;

  Future<void> _recoverStatus() async {
    try {
      Sc1WifiStatus status;
      try {
        status = await _ble.readStatus();
      } catch (_) {
        final selected = _selectedDevice;
        if (selected == null) rethrow;
        await _ble.connect(selected);
        await _ble.subscribeStatus();
        status = await _ble.readStatus();
      }
      if (!mounted) return;
      setState(() => _lastStatus = status);
      if (_credentialsSent &&
          status.state == 'connected' &&
          _isRequestedNetwork(status))
        _handleConnected(status);
      if (status.state == 'failed')
        setState(() {
          _busy = false;
          _error = _friendlyError(status.error);
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _error =
              'Bluetooth disconnected. Reconnect to the SC-1 and check its status.';
        });
    }
  }

  String _friendlyError(String? error) => switch (error) {
    'wrong_password' => 'Wrong Wi-Fi password',
    'not_found' => "SC-1 can't see that network",
    'timeout' => "The network didn't respond, move closer and try again",
    _ => "Couldn't join, try again",
  };

  IconData _signalIcon(int signal) => switch (signal) {
    >= 80 => Icons.signal_wifi_4_bar,
    >= 60 => Icons.network_wifi_3_bar,
    >= 40 => Icons.network_wifi_2_bar,
    >= 20 => Icons.network_wifi_1_bar,
    _ => Icons.signal_wifi_0_bar,
  };

  Future<void> _findController({String? fallbackIp, String? ssid}) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (c) => AlertDialog(
            title: const Text('Connect your phone to Wi-Fi'),
            content: Text(
              'Put your phone on ${ssid ?? 'the same Wi-Fi network as the SC-1'} to continue.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Continue'),
              ),
            ],
          ),
    );
    if (proceed != true || !mounted) return;
    List<ConnectivityResult> connectivity;
    try {
      connectivity = await Connectivity().checkConnectivity();
    } catch (_) {
      final targetSsid = ssid ?? 'the SC-1 Wi-Fi network';
      if (mounted)
        setState(() {
          _busy = false;
          _error =
              'Check that your phone is connected to $targetSsid, then search again.';
        });
      return;
    }
    final hasWifi = connectivity.contains(ConnectivityResult.wifi);
    final hasCellular = connectivity.contains(ConnectivityResult.mobile);
    if (!hasWifi && hasCellular) {
      setState(() {
        _busy = false;
        _error =
            'Connect your phone to ${ssid ?? 'the SC-1 Wi-Fi network'} to find the controller.';
      });
      return;
    }
    // Status.ip is the SC-1 Wi-Fi address, so verify it directly first.
    String? working;
    if (fallbackIp != null &&
        fallbackIp.isNotEmpty &&
        await _healthOk(fallbackIp)) {
      working = fallbackIp;
    }
    var found = <FoundController>[];
    if (working == null) {
      // The new Wi-Fi address can take up to 30 seconds to appear in mDNS.
      found = await ControllerDiscovery.find(
        timeout: const Duration(seconds: 30),
      );
      // A controller can announce several interfaces. Health-check all of
      // them rather than assuming the first address belongs to this network.
      final ips =
          found
              .expand((c) => c.addresses.isEmpty ? [c.ip] : c.addresses)
              .toSet();
      for (final ip in ips) {
        if (await _healthOk(ip)) {
          working = ip;
          break;
        }
      }
    }
    if (working == null) {
      if (mounted)
        setState(() {
          _busy = false;
          _error =
              'Could not reach the SC-1 over Wi-Fi. Confirm your phone is on the same network, then search again.';
        });
      return;
    }
    await ApiConfig.setIp(
      working,
      hostname:
          found
              .where((c) => c.ip == working || c.addresses.contains(working))
              .firstOrNull
              ?.hostname ??
          'SC1-${_unitNumber()}',
    );
    if (mounted)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => AppShell(isAdmin: widget.isAdmin)),
        (_) => false,
      );
  }

  Future<bool> _healthOk(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip:${ApiConfig.port}/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200 &&
          (jsonDecode(response.body) as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  String _unitNumber() =>
      _selectedDevice?.advertisementData.advName.split(' ').last ??
      'Controller';

  @override
  Widget build(BuildContext context) {
    final setupDone = _ble.info != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up SC-1'),
        actions: [
          if (setupDone)
            TextButton(
              onPressed:
                  _busy
                      ? null
                      : () {
                        final connectedStatus =
                            _lastStatus?.state == 'connected'
                                ? _lastStatus
                                : null;
                        _findController(
                          fallbackIp:
                              connectedStatus?.ip ??
                              _ble.info?['ip']?.toString(),
                          ssid:
                              connectedStatus?.ssid ??
                              _ble.info?['wifi_ssid']?.toString(),
                        );
                      },
              child: const Text('Find controller'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!setupDone) ...[
                  const Text(
                    'Bluetooth is used only to send Wi-Fi details to your SC-1. The app uses Wi-Fi for normal control.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  if (_scanning || _busy)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  Text(
                    _scanning
                        ? 'Looking for SC-1 controllers…'
                        : 'Controllers nearby',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (!_scanning && _devices.isEmpty)
                    const Text(
                      'No SC-1 found. Check it is powered on, stay within a few metres, and make sure Bluetooth is on.',
                    ),
                  for (final device in _devices)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.advertisementData.advName),
                        subtitle: Text('Signal ${device.rssi} dBm'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _connect(device),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _scanning || _busy ? null : _scan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan again'),
                  ),
                ] else if (!_ble.codeAccepted) ...[
                  const Text(
                    'This SC-1 requires the setup code printed on its sticker.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _verifySetupCode,
                    child: const Text('Enter setup code'),
                  ),
                ] else ...[
                  Text(
                    'Choose a Wi-Fi network for ${_ble.info?['name'] ?? 'your SC-1'}.',
                  ),
                  const SizedBox(height: 12),
                  if (_busy) const LinearProgressIndicator(),
                  const Text(
                    'Tap one network to select it. No network is selected automatically.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  for (final network in _networks)
                    Card(
                      color:
                          _selectedNetwork?.ssid == network.ssid &&
                                  !_otherNetwork
                              ? const Color(0xFF26384B)
                              : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color:
                              _selectedNetwork?.ssid == network.ssid &&
                                      !_otherNetwork
                                  ? Colors.lightBlueAccent
                                  : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        onTap:
                            () => setState(() {
                              _selectedNetwork = network;
                              _otherNetwork = false;
                              _error = null;
                            }),
                        leading: Icon(
                          network.secure ? Icons.lock_outline : Icons.wifi,
                        ),
                        title: Text(network.ssid),
                        subtitle: Text('Signal ${network.signal}%'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _signalIcon(network.signal),
                              color: Colors.white70,
                            ),
                            if (_selectedNetwork?.ssid == network.ssid &&
                                !_otherNetwork)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.lightBlueAccent,
                              ),
                          ],
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _loadNetworks,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh networks'),
                  ),
                  TextButton(
                    onPressed:
                        () => setState(() {
                          _otherNetwork = true;
                          _selectedNetwork = null;
                        }),
                    child: const Text('Other network…'),
                  ),
                  if (_otherNetwork)
                    TextField(
                      controller: _ssid,
                      maxLength: 32,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Network name (SSID)',
                      ),
                    ),
                  if ((_selectedNetwork?.secure ?? true)) ...[
                    TextField(
                      controller: _password,
                      maxLength: 64,
                      obscureText: !_showPassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Wi-Fi password',
                        suffixIcon: IconButton(
                          onPressed:
                              () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                  ] else if (_selectedNetwork != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'This is an open network and does not use a password.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed:
                        _busy || (!_otherNetwork && _selectedNetwork == null)
                            ? null
                            : _provision,
                    child: const Text('Connect SC-1 to Wi-Fi'),
                  ),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(
                        _lastStatus?.state == 'connecting'
                            ? 'Connecting to ${_lastStatus?.ssid ?? 'Wi-Fi'}…'
                            : 'Sending Wi-Fi details…',
                      ),
                    ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
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
