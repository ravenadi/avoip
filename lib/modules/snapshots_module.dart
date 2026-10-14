import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../models/device_model.dart';
import '../services/snapshot_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/routing_sheets.dart';
import '../logic/app_state.dart';

/// Routing presets, stored on the controller so touch panels and other
/// phones recall the same ones. A snapshot covers all screens (global) or the
/// screens picked when saving it (exclusive), and recalling it only switches
/// those screens.
class SnapshotsModule extends StatefulWidget {
  /// True when pushed as its own screen (from Operate), false as a tab.
  final bool showAppBar;

  const SnapshotsModule({super.key, this.showAppBar = false});

  @override
  State<SnapshotsModule> createState() => _SnapshotsModuleState();
}

class _SnapshotsModuleState extends State<SnapshotsModule> {
  AppState get _state => AppState.instance;

  List<Device> get _displays =>
      _state.destinationsByLocation.values.expand((d) => d).toList();

  @override
  void initState() {
    super.initState();
    _state.loadSnapshots();
    _state.currentTab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _state.currentTab.removeListener(_onTabChanged);
    super.dispose();
  }

  // Another phone or a touch panel may have changed them meanwhile.
  void _onTabChanged() {
    if (_state.currentTab.value == AppTabs.snapshots) _state.loadSnapshots();
  }

  String _nameOf(String controllerId) {
    for (final d in [..._state.sources, ..._displays]) {
      if (d.controllerId == controllerId) return d.name;
    }
    return _state.controllerDeviceNames[controllerId] ?? 'Unknown device';
  }

  Device? _sourceOf(Device display) {
    final sourceId = _state.activeRoutes[display.id];
    for (final s in _state.sources) {
      if (s.id == sourceId) return s;
    }
    return null;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? Colors.orangeAccent : Colors.greenAccent.shade400,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _showCreateSnapshotDialog() {
    final displays = _displays;
    if (displays.isEmpty) {
      _toast(
        'Adopt screens in Discovery before saving a snapshot.',
        error: true,
      );
      return;
    }

    // Only screens showing a known source can be saved.
    bool canSave(Device d) =>
        d.controllerId != null && _sourceOf(d)?.controllerId != null;
    final savable = displays.where(canSave).toList();
    if (savable.isEmpty) {
      _toast('Route a source to a screen in Operate first.', error: true);
      return;
    }

    final titleCtrl = TextEditingController();
    final selected = {for (final d in savable) d.id};
    String? error;
    var saving = false;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              final allSelected = selected.length == savable.length;
              return AlertDialog(
                scrollable: true,
                backgroundColor: AppTheme.backgroundLight,
                title: const Text(
                  'Save Snapshot',
                  style: TextStyle(color: AppTheme.accentWhite),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saves what the selected screens are showing now. '
                      'Recalling it only switches those screens.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      style: const TextStyle(color: Colors.white),
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Snapshot name',
                        labelStyle: const TextStyle(color: Colors.grey),
                        errorText: error,
                        errorMaxLines: 3,
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.accentWhite),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: allSelected,
                      onChanged:
                          (v) => setDialogState(() {
                            selected.clear();
                            if (v == true) {
                              selected.addAll(savable.map((d) => d.id));
                            }
                          }),
                      title: const Text(
                        'All screens',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: Colors.greenAccent,
                      checkColor: Colors.black,
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    for (final display in displays)
                      CheckboxListTile(
                        value: selected.contains(display.id),
                        onChanged:
                            canSave(display)
                                ? (v) => setDialogState(() {
                                  if (v == true) {
                                    selected.add(display.id);
                                  } else {
                                    selected.remove(display.id);
                                  }
                                })
                                : null,
                        title: Text(
                          display.name,
                          style: TextStyle(
                            color:
                                canSave(display) ? Colors.white : Colors.grey,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          canSave(display)
                              ? _sourceOf(display)!.name
                              : display.controllerId == null
                              ? 'Not found on the controller'
                              : 'No source',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: Colors.greenAccent,
                        checkColor: Colors.black,
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(ctx),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed:
                        saving
                            ? null
                            : () async {
                              final title = titleCtrl.text.trim();
                              if (title.isEmpty || selected.isEmpty) {
                                setDialogState(
                                  () =>
                                      error =
                                          title.isEmpty
                                              ? 'Enter a name'
                                              : 'Select at least one screen',
                                );
                                return;
                              }
                              setDialogState(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                await _state.createSnapshot(
                                  name: title,
                                  // Global covers every screen.
                                  scope:
                                      selected.length == displays.length
                                          ? 'global'
                                          : 'exclusive',
                                  routes: _state.currentSnapshotRoutes(
                                    displays.where(
                                      (d) => selected.contains(d.id),
                                    ),
                                  ),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _toast('Snapshot saved: $title');
                              } on ControllerApiException catch (e) {
                                setDialogState(() {
                                  saving = false;
                                  error = e.message;
                                });
                              }
                            },
                    child:
                        saving
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                            : const Text('Save'),
                  ),
                ],
              );
            },
          ),
    ).whenComplete(titleCtrl.dispose);
  }

  // ── Edit ──────────────────────────────────────────────────────────────────

  Future<void> _rename(ControllerSnapshot snapshot) async {
    final ctrl = TextEditingController(text: snapshot.name);
    final name = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.backgroundLight,
            title: const Text(
              'Rename snapshot',
              style: TextStyle(color: AppTheme.accentWhite),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Snapshot name',
                labelStyle: TextStyle(color: Colors.grey),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || name == snapshot.name) return;
    try {
      await _state.updateSnapshot(
        snapshot.id,
        name: name,
        scope: snapshot.scope,
        routes: snapshot.routes,
      );
      _toast('Renamed to $name');
    } on ControllerApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  // Re-saves the same screens with what they show now; the id stays, so
  // touch panel buttons keep working.
  Future<void> _updateRouting(ControllerSnapshot snapshot) async {
    final displays =
        snapshot.isGlobal
            ? _displays
            : _displays.where(
              (d) => snapshot.routes.any((r) => r.rxId == d.controllerId),
            );
    final routes = _state.currentSnapshotRoutes(displays);
    if (routes.isEmpty) {
      _toast("None of this snapshot's screens has a source now.", error: true);
      return;
    }
    try {
      await _state.updateSnapshot(
        snapshot.id,
        name: snapshot.name,
        scope: snapshot.scope,
        routes: routes,
      );
      _toast('"${snapshot.name}" updated with the current routing');
    } on ControllerApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _confirmDelete(ControllerSnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.backgroundLight,
            title: const Text(
              'Delete snapshot?',
              style: TextStyle(color: AppTheme.accentWhite),
            ),
            content: Text(
              '"${snapshot.name}" will be removed from the controller, '
              'including for touch panels. This can\'t be undone.',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await _state.deleteSnapshot(snapshot.id);
    } on ControllerApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _copyRecallUrl(ControllerSnapshot snapshot) async {
    await Clipboard.setData(
      ClipboardData(text: SnapshotService.recallUrl(snapshot.id)),
    );
    _toast('Recall URL copied (POST) for touch panels');
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _state.stateVersionNotifier,
      builder: (context, _, child) {
        final isMobile = MediaQuery.of(context).size.width < 700;

        return Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          appBar:
              widget.showAppBar
                  ? AppBar(
                    backgroundColor: AppTheme.backgroundLight,
                    elevation: 0,
                    title: const Text(
                      'Snapshots',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                  : null,
          body: RefreshIndicator(
            onRefresh: _state.loadSnapshots,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Snapshots',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed:
                            _state.snapshotsError?.unsupported == true
                                ? null
                                : _showCreateSnapshotDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.greenAccent,
                          side: const BorderSide(color: Colors.greenAccent),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Presets saved on the controller. Touch panels can recall '
                    'them too.',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 24),
                  _buildBody(isMobile ? 12.0 : 16.0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(double spacing) {
    final error = _state.snapshotsError;
    final snapshots = _state.snapshots;

    if (_state.snapshotsLoading && snapshots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.accentWhite),
        ),
      );
    }
    if (error != null) {
      return _message(
        error.unsupported
            ? Icons.system_update_alt_rounded
            : Icons.cloud_off_rounded,
        error.unsupported
            ? 'Controller update needed'
            : "Couldn't load snapshots",
        error.message,
        onRetry: _state.loadSnapshots,
      );
    }
    if (snapshots.isEmpty) {
      return _message(
        Icons.camera_enhance_outlined,
        'No snapshots yet',
        'Route your screens in Operate, then tap New.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 420).ceil().clamp(1, 3);
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final snapshot in snapshots)
              SizedBox(width: width, child: _buildSnapshotCard(snapshot)),
          ],
        );
      },
    );
  }

  Widget _message(
    IconData icon,
    String title,
    String detail, {
    VoidCallback? onRetry,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.grey.shade700),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotCard(ControllerSnapshot snapshot) {
    final lines = [
      for (final r in snapshot.routes)
        '${_nameOf(r.rxId)}  ←  ${_nameOf(r.txId)}',
    ];
    const maxLines = 3;

    return AvCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  snapshot.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _scopeChip(snapshot.isGlobal),
              _menu(snapshot),
            ],
          ),
          const SizedBox(height: 8),
          if (lines.isEmpty)
            const Text(
              'No screens in this snapshot.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          for (final line in lines.take(maxLines))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (lines.length > maxLines)
            Text(
              '+${lines.length - maxLines} more',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          const SizedBox(height: 4),
          Text(
            'ID: ${snapshot.id}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  () => recallSnapshot(ScaffoldMessenger.of(context), snapshot),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Recall'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentWhite,
                foregroundColor: AppTheme.backgroundLight,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu(ControllerSnapshot snapshot) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
      tooltip: 'More',
      color: AppTheme.highlightGrey,
      onSelected: (action) {
        switch (action) {
          case 'rename':
            _rename(snapshot);
          case 'update':
            _updateRouting(snapshot);
          case 'copy':
            _copyRecallUrl(snapshot);
          case 'delete':
            _confirmDelete(snapshot);
        }
      },
      itemBuilder:
          (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(
              value: 'update',
              child: Text('Update with current routing'),
            ),
            PopupMenuItem(value: 'copy', child: Text('Copy recall URL')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
    );
  }

  Widget _scopeChip(bool isGlobal) {
    final color = isGlobal ? Colors.greenAccent : Colors.lightBlueAccent;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isGlobal ? 'GLOBAL' : 'EXCLUSIVE',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
