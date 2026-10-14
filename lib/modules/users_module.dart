import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../logic/app_state.dart';

class UsersModule extends StatefulWidget {
  const UsersModule({super.key});

  @override
  State<UsersModule> createState() => _UsersModuleState();
}

class _UsersModuleState extends State<UsersModule> {
  String _searchQuery = '';

  List<UserAccount> get _filteredUsers {
    if (_searchQuery.isEmpty) return AppState.instance.users;
    return AppState.instance.users.where((u) {
      return u.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             u.role.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _showAddUserDialog() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String selectedRole = 'User';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          scrollable: true,
          backgroundColor: AppTheme.backgroundLight,
          title: const Text('Provision New User', style: TextStyle(color: AppTheme.accentWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Username', labelStyle: TextStyle(color: Colors.grey)),
              ),
              TextField(
                controller: passwordCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Password', labelStyle: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                dropdownColor: AppTheme.backgroundLight,
                style: const TextStyle(color: Colors.white),
                items: ['Admin', 'User'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setStateDialog(() {
                      selectedRole = newValue;
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Access Role', labelStyle: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentWhite, foregroundColor: Colors.black),
              onPressed: () {
                if (usernameCtrl.text.isNotEmpty && passwordCtrl.text.isNotEmpty) {
                  final newUser = UserAccount(
                    id: 'u_${DateTime.now().millisecondsSinceEpoch}',
                    username: usernameCtrl.text,
                    password: passwordCtrl.text,
                    role: selectedRole,
                  );
                  setState(() {
                    AppState.instance.users.add(newUser);
                    AppState.instance.notifyListeners(); // Notify if other widgets care
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create User'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteUser(UserAccount user) {
    // Prevent deleting the root admin to avoid lockout
    if (user.username == 'admin' && user.id == 'u1') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the master root admin.')),
      );
      return;
    }

    setState(() {
      AppState.instance.users.removeWhere((u) => u.id == user.id);
      AppState.instance.notifyListeners();
    });
  }

  void _showEditUserDialog(UserAccount user) {
    if (user.username == 'admin' && user.id == 'u1') {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot modify the master root admin via interface.')),
      );
      return;
    }

    final usernameCtrl = TextEditingController(text: user.username);
    final passwordCtrl = TextEditingController(text: user.password);
    String selectedRole = user.role;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          scrollable: true,
          backgroundColor: AppTheme.backgroundLight,
          title: const Text('Edit User Access', style: TextStyle(color: AppTheme.accentWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Username', labelStyle: TextStyle(color: Colors.grey)),
              ),
              TextField(
                controller: passwordCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Password', labelStyle: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                dropdownColor: AppTheme.backgroundLight,
                style: const TextStyle(color: Colors.white),
                items: ['Admin', 'User'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    setStateDialog(() {
                      selectedRole = newValue;
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Access Role', labelStyle: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteUser(user);
              },
              child: const Text('Delete User', style: TextStyle(color: Colors.redAccent)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentWhite, foregroundColor: Colors.black),
              onPressed: () {
                if (usernameCtrl.text.isNotEmpty && passwordCtrl.text.isNotEmpty) {
                  setState(() {
                    final index = AppState.instance.users.indexWhere((u) => u.id == user.id);
                    if (index != -1) {
                      AppState.instance.users[index] = UserAccount(
                        id: user.id,
                        username: usernameCtrl.text,
                        password: passwordCtrl.text,
                        role: selectedRole,
                      );
                      AppState.instance.notifyListeners();
                    }
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Row(
        children: [
          Expanded(
            child: Container(
              color: AppTheme.backgroundLight,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundLight,
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isSmall = constraints.maxWidth < 600;
                            return isSmall 
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'User Management',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.accentWhite,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        ),
                                        onPressed: _showAddUserDialog,
                                        icon: const Icon(Icons.person_add_outlined, size: 18),
                                        label: const Text('Provision User', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'User Management',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.accentWhite,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      ),
                                      onPressed: _showAddUserDialog,
                                      icon: const Icon(Icons.person_add_outlined, size: 18),
                                      label: const Text('Provision User', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                );
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: TextField(
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              icon: Icon(Icons.search, color: Colors.white54),
                              hintText: 'Search by username or role...',
                              hintStyle: TextStyle(color: Colors.white30),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: _filteredUsers.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        final isAdmin = user.role == 'Admin';
                        
                        return Container(
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: isAdmin ? Colors.purpleAccent.withValues(alpha: 0.2) : Colors.blueAccent.withValues(alpha: 0.2),
                              child: Icon(
                                isAdmin ? Icons.admin_panel_settings : Icons.person,
                                color: isAdmin ? Colors.purpleAccent : Colors.blueAccent,
                              ),
                            ),
                            title: Text(
                              user.username,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            subtitle: Row(
                              children: [
                                Icon(Icons.badge_outlined, size: 14, color: Colors.white54),
                                const SizedBox(width: 4),
                                Text(
                                  user.role,
                                  style: TextStyle(color: isAdmin ? Colors.purpleAccent : Colors.blueAccent, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            trailing: TextButton.icon(
                              onPressed: () => _showEditUserDialog(user),
                              icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white70),
                              label: const Text('Edit', style: TextStyle(color: Colors.white70)),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.05),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
