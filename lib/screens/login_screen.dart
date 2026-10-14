import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'server_setup_screen.dart';
import '../logic/app_state.dart';
import '../config/session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;

  void _executeLogin() async {
    final u = _usernameCtrl.text.trim();
    final p = _passwordCtrl.text.trim();

    if (u.isEmpty || p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter credentials.')));
      return;
    }

    setState(() => _isLoading = true);

    // Evaluate credentials against the active RBAC engine
    try {
      final matchedUser = AppState.instance.users.firstWhere(
        (user) => user.username == u && user.password == p,
      );

      if (_rememberMe) {
        await Session.remember(matchedUser.username);
      } else {
        await Session.forget();
      }

      // Launch application with retrieved security privileges
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ServerSetupScreen(isAdmin: matchedUser.role == 'Admin')),
        );
      }
    } catch (_) {
      // Catch StateError when firstWhere fails to locate credentials
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid username or password.'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppTheme.backgroundLight),
          Container(color: Colors.black.withValues(alpha: 0.6)),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xAA000000), AppTheme.backgroundLight],
                stops: [0.0, 0.7, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      'The Authentic AV experience.\nCinematic in every sense.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Authenticate for Control.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                    const SizedBox(height: 64),
                    // Credential Fields
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
                            controller: _usernameCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              labelStyle: TextStyle(color: Colors.grey),
                              prefixIcon: Icon(Icons.person_outline, color: Colors.white54),
                              border: InputBorder.none,
                            ),
                          ),
                          const Divider(color: Colors.white10),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              labelStyle: TextStyle(color: Colors.grey),
                              prefixIcon: Icon(Icons.lock_outline, color: Colors.white54),
                              border: InputBorder.none,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                  activeColor: AppTheme.accentWhite,
                                  checkColor: Colors.black,
                                  side: const BorderSide(color: Colors.white54),
                                ),
                                const Flexible(
                                  child: Text('Remember me', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _executeLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentWhite,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading 
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                  : const Text('Access Matrix', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
        ],
      ),
    );
  }
}
