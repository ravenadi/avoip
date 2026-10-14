import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/controller_discovery.dart';
import '../services/database_service.dart';

/// Holds the controller's address. The client picks the controller found on
/// the network (or types its IP) after login, see ServerSetupScreen. Both the
/// IP and the controller's hostname are saved, so that when DHCP gives the
/// controller a new IP the app can find it again by hostname.
class ApiConfig {
  static const String _ipKey = 'server_ip';
  static const String _hostnameKey = 'server_hostname';
  static const int port = 8000;

  // Don't browse the network more often than this when the IP stops working.
  static const Duration _rediscoveryInterval = Duration(seconds: 30);

  static String? _ip;
  static String? _hostname;
  static DateTime? _lastRediscovery;
  static Future<bool>? _rediscovery;

  static String? get ip => _ip;

  /// The controller's hostname (e.g. "SC1-2063") if it was picked from the
  /// network rather than typed in.
  static String? get hostname => _hostname;

  static bool get isConfigured => _ip != null && _ip!.trim().isNotEmpty;

  // Always [port] in the app; tests point at a local fake controller.
  static int _port = port;

  static String get baseUrl => 'http://$_ip:$_port';

  /// Loads the last-saved controller, if any. Call once at startup.
  static Future<void> loadSaved() async {
    _ip = await DatabaseService.instance.loadSetting(_ipKey);
    _hostname = await DatabaseService.instance.loadSetting(_hostnameKey);
  }

  /// Points the app at [ip]:[testPort] without saving it (tests only).
  @visibleForTesting
  static void useForTesting(String ip, {int testPort = port}) {
    _ip = ip;
    _port = testPort;
    _hostname = null;
  }

  /// Saves the controller to use. Pass [hostname] when it came from network
  /// discovery; a typed-in IP has none.
  static Future<void> setIp(String ip, {String? hostname}) async {
    _ip = ip.trim();
    _hostname = hostname;
    await DatabaseService.instance.saveSetting(_ipKey, _ip!);
    if (hostname == null) {
      await DatabaseService.instance.deleteSetting(_hostnameKey);
    } else {
      await DatabaseService.instance.saveSetting(_hostnameKey, hostname);
    }
  }

  /// Looks for the saved controller on the network and switches to its new
  /// IP. Matches by hostname, or takes the only controller found when the IP
  /// was typed in. Returns true if the IP changed.
  static Future<bool> rediscover() {
    final running = _rediscovery;
    if (running != null) return running;
    final last = _lastRediscovery;
    if (last != null &&
        DateTime.now().difference(last) < _rediscoveryInterval) {
      return Future.value(false);
    }
    _lastRediscovery = DateTime.now();
    return _rediscovery = _findAgain().whenComplete(() => _rediscovery = null);
  }

  static Future<bool> _findAgain() async {
    final found = await ControllerDiscovery.find();
    final candidates =
        _hostname != null
            ? found.where((c) => c.hostname == _hostname).toList()
            : found.length == 1
            ? found
            : <FoundController>[];
    for (final candidate in candidates) {
      if (!await _responds(candidate.ip)) continue;
      if (candidate.ip == _ip) return false;
      await setIp(candidate.ip, hostname: candidate.hostname ?? _hostname);
      return true;
    }
    return false;
  }

  static Future<bool> _responds(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip:$_port/health'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return false;
      return (jsonDecode(response.body) as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}
