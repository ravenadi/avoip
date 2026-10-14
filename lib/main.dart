import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'logic/app_state.dart';
import 'config/api_config.dart';
import 'config/session.dart';
import 'widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.loadFromDatabase();
  await ApiConfig.loadSaved();
  await Session.loadSaved();
  runApp(const AuthenticAvApp());
}

class AuthenticAvApp extends StatelessWidget {
  const AuthenticAvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuthenticAV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Follow the phone's text size, but not so far that layouts break.
      builder:
          (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: child!,
          ),
      home: _startScreen(),
    );
  }

  // "Remember me" with a known server goes straight into the app.
  Widget _startScreen() {
    final user = Session.rememberedUser;
    if (user != null && ApiConfig.isConfigured) {
      return AppShell(isAdmin: user.role == 'Admin');
    }
    return const LoginScreen();
  }
}
