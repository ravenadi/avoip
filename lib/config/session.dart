import '../logic/app_state.dart';
import '../services/database_service.dart';

/// "Remember me": keeps the signed-in username (never the password) so the
/// next launch can skip the login and server screens.
class Session {
  static const String _settingKey = 'remembered_user';

  static String? _username;

  /// Loads the remembered username, if any. Call once at startup.
  static Future<void> loadSaved() async {
    _username = await DatabaseService.instance.loadSetting(_settingKey);
  }

  /// The remembered account, if it still exists.
  static UserAccount? get rememberedUser {
    final name = _username;
    if (name == null) return null;
    for (final user in AppState.instance.users) {
      if (user.username == name) return user;
    }
    return null;
  }

  static Future<void> remember(String username) async {
    _username = username;
    await DatabaseService.instance.saveSetting(_settingKey, username);
  }

  static Future<void> forget() async {
    _username = null;
    await DatabaseService.instance.deleteSetting(_settingKey);
  }
}
