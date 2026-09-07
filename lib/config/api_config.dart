import '../services/database_service.dart';

/// Holds the backend device-registry/command API host, entered by the
/// client after login (see ServerSetupScreen) instead of being hardcoded.
/// The IP is persisted so it survives app restarts.
class ApiConfig {
  static const String _settingKey = 'server_ip';
  static const int port = 8000;

  static String? _ip;

  static String? get ip => _ip;

  static bool get isConfigured => _ip != null && _ip!.trim().isNotEmpty;

  static String get baseUrl => 'http://$_ip:$port';

  /// Loads the last-saved server IP from disk, if any. Call once at startup.
  static Future<void> loadSaved() async {
    _ip = await DatabaseService.instance.loadSetting(_settingKey);
  }

  /// Sets and persists the server IP entered by the client.
  static Future<void> setIp(String ip) async {
    _ip = ip.trim();
    await DatabaseService.instance.saveSetting(_settingKey, _ip!);
  }
}
