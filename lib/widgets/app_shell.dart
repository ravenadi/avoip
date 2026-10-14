import 'dart:async';
import 'package:flutter/material.dart';
import '../logic/app_state.dart';
import '../theme/app_theme.dart';
import '../modules/operate_module.dart';
import '../modules/discovery_module.dart';
import '../modules/configuration_module.dart';
import '../modules/snapshots_module.dart';
import '../modules/help_module.dart';
import '../modules/users_module.dart';
import '../modules/utilities_module.dart';
import '../screens/login_screen.dart';
import '../config/session.dart';

class AppShell extends StatefulWidget {
  final bool isAdmin;
  const AppShell({super.key, required this.isAdmin});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  // Controller device ids (and so preview URLs) change when it restarts, so
  // the device list is reloaded on screen open, on resume and on this timer.
  static const Duration _deviceRefreshInterval = Duration(seconds: 45);

  int _selectedIndex = 0;
  Timer? _deviceRefreshTimer;

  // 'id' is what AppState.currentTab holds (see AppTabs).
  final List<Map<String, dynamic>> _allNavItems = [
    {'id': AppTabs.discovery, 'icon': Icons.manage_search_outlined, 'label': 'Discovery', 'adminOnly': true, 'module': const DiscoveryModule()},
    {'id': AppTabs.configuration, 'icon': Icons.settings_outlined, 'label': 'Configuration', 'adminOnly': true, 'module': const ConfigurationModule()},
    {'id': AppTabs.operate, 'icon': Icons.settings_input_component_outlined, 'label': 'Operate', 'module': const OperateModule()},
    {'id': AppTabs.snapshots, 'icon': Icons.camera_alt_outlined, 'label': 'Snapshots', 'module': const SnapshotsModule()},
    {'id': AppTabs.users, 'icon': Icons.admin_panel_settings_outlined, 'label': 'User Management', 'adminOnly': true, 'module': const UsersModule()},
    {'id': AppTabs.utilities, 'icon': Icons.monitor_heart_outlined, 'label': 'Utilities', 'adminOnly': true, 'module': const UtilitiesModule()},
    {'id': AppTabs.help, 'icon': Icons.help_outline, 'label': 'Help', 'module': const HelpModule()},
  ];

  List<Map<String, dynamic>> get _visibleItems =>
      widget.isAdmin
          ? _allNavItems
          : _allNavItems.where((item) => item['adminOnly'] != true).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Admins start in Discovery until a device is adopted; then, like
    // everyone else, in Operate.
    final hasDevices =
        AppState.instance.sources.isNotEmpty ||
        AppState.instance.destinationsByLocation.isNotEmpty;
    final startTab =
        widget.isAdmin && !hasDevices ? AppTabs.discovery : AppTabs.operate;
    _selectedIndex = _visibleItems.indexWhere((i) => i['id'] == startTab);
    AppState.instance.currentTab.value = startTab;
    AppState.instance.currentTab.addListener(_syncTabIndex);
    AppState.instance.refreshDevices();
    _deviceRefreshTimer = Timer.periodic(_deviceRefreshInterval, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        AppState.instance.refreshDevices();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppState.instance.refreshDevices();
  }

  // Tab changes go through the shared notifier so it always matches the
  // visible tab (Discovery uses it to jump to Configuration after adopting).
  void _selectTab(int index) {
    AppState.instance.currentTab.value = _visibleItems[index]['id'] as String;
  }

  void _syncTabIndex() {
    if (!mounted) return;
    final index = _visibleItems.indexWhere(
      (i) => i['id'] == AppState.instance.currentTab.value,
    );
    if (index < 0) return;
    setState(() => _selectedIndex = index);
    AppState.instance.refreshDevices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceRefreshTimer?.cancel();
    AppState.instance.currentTab.removeListener(_syncTabIndex);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    if (_selectedIndex < 0 || _selectedIndex >= visibleItems.length) {
      _selectedIndex = 0;
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        toolbarHeight: isMobile ? 60 : 70,
        backgroundColor: AppTheme.backgroundLight, // Sleek Pitch Black Apple TV Header
        elevation: 0,
        title: Row(
          children: [
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Authentic AV',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 12, color: Colors.grey.shade600),
                    ],
                  ),
                  Text(
                    visibleItems[_selectedIndex]['label'],
                    style: const TextStyle(fontSize: 17, color: AppTheme.accentWhite, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
                color: AppTheme.accentWhite,
                size: 18,
              ),
              if (!isMobile) ...[
                const SizedBox(width: 6),
                Text(
                  widget.isAdmin ? 'Admin' : 'User',
                  style: const TextStyle(
                    color: AppTheme.accentWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.logout_outlined, color: AppTheme.accentWhite, size: 20),
                tooltip: 'Logout',
                onPressed: () {
                  // Logging out also ends "Remember me".
                  Session.forget();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ), // closes AppBar
      drawer: Drawer(
        backgroundColor: AppTheme.backgroundLight,
        child: Column(
          children: [
            const SizedBox(height: 60),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade800, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Image(
                        image: AssetImage('assets/images/auth.av_purple-white.png'),
                        height: 60,
                        width: 60,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Authentic AV',
                      style: TextStyle(
                        color: AppTheme.accentWhite,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'New York',
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'EXPERIENCE CONTROL',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(color: Colors.grey.shade900, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: visibleItems.length,
                itemBuilder: (context, index) {
                  final item = visibleItems[index];
                  final isSelected = _selectedIndex == index;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    dense: true,
                    leading: Icon(
                      item['icon'] as IconData,
                      size: 20,
                      color: isSelected ? AppTheme.accentWhite : AppTheme.textMuted,
                    ),
                    title: Text(
                      item['label'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppTheme.accentWhite : AppTheme.textMuted,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: AppTheme.highlightGrey,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    style: ListTileStyle.drawer,
                    onTap: () {
                      _selectTab(index);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Hidden tabs keep their state but stop tickers and preview polling.
          for (int i = 0; i < visibleItems.length; i++)
            TickerMode(
              enabled: i == _selectedIndex,
              child: visibleItems[i]['module'] as Widget,
            ),
        ],
      ),
    );
  }
}
