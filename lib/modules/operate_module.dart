import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/device_model.dart';
import '../logic/app_state.dart';
import '../screens/live_view_screen.dart';
import '../widgets/device_preview.dart';
import '../widgets/routing_sheets.dart';
import '../services/snapshot_service.dart';
import 'snapshots_module.dart';

class OperateModule extends StatefulWidget {
  const OperateModule({super.key});

  @override
  State<OperateModule> createState() => _OperateModuleState();
}

class _OperateModuleState extends State<OperateModule> {
  ViewMode _viewMode = ViewMode.largeGrid;
  bool _isSourcesView = false;

  Map<String, String?> get _activeRoutes => AppState.instance.activeRoutes;
  List<Device> get _sources => AppState.instance.sources;
  Map<String, List<Device>> get _destinationsByLocation =>
      AppState.instance.destinationsByLocation;

  final Map<String, bool> _expandedLocations = {};
  String? _selectedDestinationId;

  List<Device> get _allDestinations =>
      _destinationsByLocation.values.expand((d) => d).toList();

  @override
  void initState() {
    super.initState();
    for (final loc in _destinationsByLocation.keys) {
      _expandedLocations[loc] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppState.instance.stateVersionNotifier,
      builder: (context, _, child) {
        final isMobile = MediaQuery.of(context).size.width < 600;
        return Column(
          children: [
            _buildControlHeader(isMobile),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 12 : 20),
                child: _isSourcesView 
                  ? _buildSourcesList(isMobile)
                  : _buildDestinationsList(isMobile),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDestinationsList(bool isMobile) {
    if (_destinationsByLocation.isEmpty) {
      return _emptyState('No displays yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          _destinationsByLocation.entries.map((entry) {
            return _buildLocationGroup(
              entry.key,
              entry.value,
              isMobile,
            );
          }).toList(),
    );
  }

  Widget _emptyState(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          '$title\nDevices adopted in Discovery appear here.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildSourcesList(bool isMobile) {
    if (_sources.isEmpty) return _emptyState('No sources yet.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active Transmitters',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 400,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 100,
          ),
          itemCount: _sources.length,
          itemBuilder: (context, index) {
            final source = _sources[index];
            final routedCount = _activeRoutes.values.where((v) => v == source.id).length;
            
            return InkWell(
              onTap: () => showDisplayPicker(context, source),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.highlightGrey,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    if (source.previewUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 85,
                          height: 48,
                          child: PolledPreview(
                            key: ValueKey(source.id),
                            url: source.previewUrl!,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.cast_rounded, color: Colors.purpleAccent),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(source.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          Text(source.ip, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: routedCount > 0 ? Colors.greenAccent.withValues(alpha: 0.1) : Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$routedCount Active',
                        style: TextStyle(
                          color: routedCount > 0 ? Colors.greenAccent : Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildControlHeader(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        border: Border(bottom: BorderSide(color: Colors.grey.shade900)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Operate',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isSourcesView ? '${_sources.length} Src' : '${_allDestinations.length} Disp',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SnapshotsModule(showAppBar: true)));
                },
                icon: const Icon(Icons.auto_awesome_motion_rounded, color: Colors.amberAccent, size: 20),
                tooltip: 'Snapshots',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 12),
                _buildDisplaysSourcesToggle(isMobile),
                const SizedBox(width: 12),
                _buildViewModeSwitcher(),
                const SizedBox(width: 12),
                _buildQuickActions(),
              ],
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 8),
            // Wraps onto another line when large text makes it too wide.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildDisplaysSourcesToggle(isMobile),
                _buildViewModeSwitcher(),
                _buildQuickActions(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDisplaysSourcesToggle(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewModeToggleCap('_isSourcesView', false, isMobile ? 'D' : 'Displays', Icons.monitor),
          _viewModeToggleCap('_isSourcesView', true, isMobile ? 'S' : 'Sources', Icons.cast),
        ],
      ),
    );
  }

  Widget _buildViewModeSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewModeCapsule(ViewMode.largeGrid, Icons.grid_view_rounded),
          Container(width: 1, height: 16, color: Colors.grey.shade800),
          _viewModeCapsule(ViewMode.compactGrid, Icons.grid_on_rounded),
          Container(width: 1, height: 16, color: Colors.grey.shade800),
          _viewModeCapsule(ViewMode.list, Icons.view_list_rounded),
        ],
      ),
    );
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.orangeAccent : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Saves every screen's current source as a snapshot on the controller.
  Future<void> _quickSave() async {
    final displays = _allDestinations;
    final routes = AppState.instance.currentSnapshotRoutes(displays);
    if (routes.isEmpty) {
      _toast('Route a source to a screen first.', error: true);
      return;
    }
    final now = DateTime.now();
    final name =
        'Quick Save ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    try {
      await AppState.instance.createSnapshot(
        name: name,
        scope: routes.length == displays.length ? 'global' : 'exclusive',
        routes: routes,
      );
      _toast('Snapshot saved: $name');
    } on ControllerApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  // Recalls the newest snapshot on the controller.
  Future<void> _recallLatest() async {
    final messenger = ScaffoldMessenger.of(context);
    await AppState.instance.loadSnapshots();
    final error = AppState.instance.snapshotsError;
    if (error != null) {
      _toast(error.message, error: true);
      return;
    }
    final snapshots = [...AppState.instance.snapshots];
    if (snapshots.isEmpty) {
      _toast('No snapshots saved yet.', error: true);
      return;
    }
    snapshots.sort(
      (a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
    );
    await recallSnapshot(messenger, snapshots.last);
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _quickSave,
          icon: const Icon(Icons.save_outlined, color: Colors.greenAccent, size: 20),
          tooltip: 'Quick Save State',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _recallLatest,
          icon: const Icon(Icons.history_rounded, color: Colors.blueAccent, size: 20),
          tooltip: 'Recall Last',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _viewModeToggleCap(String property, bool value, String label, IconData icon) {
    final isSelected = _isSourcesView == value;
    return InkWell(
      onTap: () => setState(() => _isSourcesView = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade800 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _viewModeCapsule(ViewMode mode, IconData icon) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade800 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? AppTheme.accentWhite : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildLocationGroup(
    String location,
    List<Device> devices,
    bool isMobile,
  ) {
    final isExpanded = _expandedLocations[location] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.highlightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap:
                () =>
                    setState(() => _expandedLocations[location] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      location,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${devices.length} display${devices.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child:
                  _viewMode != ViewMode.list
                      ? GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent:
                              _viewMode == ViewMode.largeGrid ? 260 : 160,
                          crossAxisSpacing: isMobile ? 12 : 16,
                          mainAxisSpacing: isMobile ? 12 : 16,
                          mainAxisExtent:
                              _viewMode == ViewMode.largeGrid ? 200 : 180,
                        ),
                        itemCount: devices.length,
                        itemBuilder: (ctx, i) => _buildGridCard(devices[i]),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: devices.length,
                        itemBuilder: (ctx, i) => _buildListCard(devices[i]),
                      ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGridCard(Device dest) {
    final activeSourceId = _activeRoutes[dest.id];
    final activeSource =
        activeSourceId != null
            ? _sources.cast<Device?>().firstWhere(
              (s) => s?.id == activeSourceId,
              orElse: () => null,
            )
            : null;
    final isSelected = _selectedDestinationId == dest.id;

    return GestureDetector(
      onLongPress: () => _showDeleteDeviceDialog(dest),
      onTap: () {
        setState(() {
          if (_selectedDestinationId == dest.id) {
            _selectedDestinationId = null;
          } else {
            _selectedDestinationId = dest.id;
          }
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : Colors.grey.shade800,
            width: isSelected ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  isSelected
                      ? Colors.greenAccent.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.3),
              blurRadius: isSelected ? 15 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              Expanded(child: _buildVideoPreview(dest, activeSource)),
              Container(
                color: Colors.black,
                padding: EdgeInsets.symmetric(
                  horizontal: _viewMode == ViewMode.compactGrid ? 4 : 16,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dest.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _viewMode == ViewMode.compactGrid ? 11 : 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.cast_connected,
                          size: _viewMode == ViewMode.compactGrid ? 9 : 10,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            activeSource?.name ?? 'None',
                            style: TextStyle(
                              color:
                                  activeSource != null
                                      ? Colors.greenAccent
                                      : Colors.grey.shade600,
                              fontSize:
                                  _viewMode == ViewMode.compactGrid ? 10 : 11,
                              fontWeight:
                                  activeSource != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _pickSource(dest),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Center(
                            child: Text(
                              'Select Source',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListCard(Device dest) {
    final activeSourceId = _activeRoutes[dest.id];
    final activeSource =
        activeSourceId != null
            ? _sources.cast<Device?>().firstWhere(
              (s) => s?.id == activeSourceId,
              orElse: () => null,
            )
            : null;
    final isSelected = _selectedDestinationId == dest.id;

    return GestureDetector(
      onLongPress: () => _showDeleteDeviceDialog(dest),
      onTap: () {
        setState(() {
          if (_selectedDestinationId == dest.id) {
            _selectedDestinationId = null;
          } else {
            _selectedDestinationId = dest.id;
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : Colors.grey.shade800,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _buildVideoPreview(
                    dest,
                    activeSource,
                    showOverlay: false,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dest.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.cast_connected,
                          size: 12,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            activeSource?.name ?? 'No Source',
                            style: TextStyle(
                              color:
                                  activeSource != null
                                      ? Colors.greenAccent
                                      : Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight:
                                  activeSource != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _pickSource(dest),
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Select Source',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDeviceDialog(Device dest) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Remove Display', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove "${dest.name}" from ${dest.location}?',
          style: TextStyle(color: Colors.grey.shade300),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              if (_selectedDestinationId == dest.id) {
                setState(() => _selectedDestinationId = null);
              }
              await AppState.instance.removeDevice(dest.id, dest.location);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Removed ${dest.name}')),
                );
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview(
    Device dest,
    Device? routedSource, {
    bool showOverlay = true,
  }) {
    // What the display itself is showing; else the routed source's frame.
    final previewUrl = dest.previewUrl ?? routedSource?.previewUrl;

    if (previewUrl != null || routedSource != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          previewUrl != null
              ? PolledPreview(key: ValueKey(dest.id), url: previewUrl)
              : DeviceThumbnail(device: routedSource!),
          if (showOverlay && routedSource != null)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  routedSource.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (showOverlay &&
              _selectedDestinationId == dest.id &&
              (dest.streamUrl != null || dest.previewUrl != null))
            Positioned(bottom: 6, right: 6, child: _fullscreenButton(dest)),
        ],
      );
    }

    return Container(
      color: Colors.grey.shade900,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_outlined, size: 24, color: Colors.grey.shade700),
            if (showOverlay) ...[
              const SizedBox(height: 4),
              const Text(
                'NO SIGNAL',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickSource(Device dest) async {
    final applied = await showSourcePicker(context, dest);
    if (applied && mounted) setState(() => _selectedDestinationId = null);
  }

  // Opens the display's full-screen live stream.
  Widget _fullscreenButton(Device dest) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
        tooltip: 'Full screen live view',
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        onPressed: () => LiveViewScreen.open(context, dest),
      ),
    );
  }
}
