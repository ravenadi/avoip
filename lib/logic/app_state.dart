import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/device_model.dart';
import '../modules/discovery_module.dart';
import '../services/database_service.dart';
import '../services/device_api_service.dart';
import '../services/snapshot_service.dart';

class UserAccount {
  final String id;
  final String username;
  final String password;
  final String role;

  UserAccount({
    required this.id,
    required this.username,
    required this.password,
    required this.role,
  });
}

/// Ids of the main menu tabs, used to switch tabs from anywhere.
class AppTabs {
  static const discovery = 'discovery';
  static const configuration = 'configuration';
  static const operate = 'operate';
  static const snapshots = 'snapshots';
  static const users = 'users';
  static const utilities = 'utilities';
  static const help = 'help';
}

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._internal();
  AppState._internal() {
    _seedDefaultUsers();
  }

  bool isLoaded = false;

  // Active Device Registries
  final List<Device> sources = [];
  final Map<String, List<Device>> destinationsByLocation = {};

  // Security/RBAC Authentication Registry
  final List<UserAccount> users = [];

  // Active Matrix Routing Paths (Destination ID -> Source ID)
  final Map<String, String?> activeRoutes = {};

  // Routing presets, stored on the controller so touch panels share them.
  List<ControllerSnapshot> snapshots = [];
  ControllerApiException? snapshotsError;
  bool snapshotsLoading = false;

  // Global Notifiers for listeners
  final ValueNotifier<int> stateVersionNotifier = ValueNotifier<int>(0);
  // Id of the visible tab (one of AppTabs).
  final ValueNotifier<String> currentTab = ValueNotifier<String>('');

  // Track the most recently adopted device to auto-focus in Configuration
  String? lastAdoptedDeviceId;

  // Built-in login accounts; users aren't persisted yet.
  void _seedDefaultUsers() {
    users.addAll([
      UserAccount(id: 'u1', username: 'admin', password: '123', role: 'Admin'),
      UserAccount(
        id: 'u2',
        username: 'operator',
        password: '123',
        role: 'User',
      ),
    ]);
  }

  // ── Database Load (called once on app start) ───────────────────────────────

  Future<void> loadFromDatabase() async {
    if (isLoaded) return;

    final db = DatabaseService.instance;

    // Load adopted devices
    final devices = await db.loadAdoptedDevices();
    for (final device in devices) {
      if (device.type == DeviceType.tx) {
        if (!sources.any((s) => s.id == device.id)) {
          sources.add(device);
        }
      } else {
        final loc = device.location;
        destinationsByLocation.putIfAbsent(loc, () => []);
        if (!destinationsByLocation[loc]!.any((d) => d.id == device.id)) {
          destinationsByLocation[loc]!.add(device);
        }
      }
    }

    // Load active routes
    final routes = await db.loadActiveRoutes();
    activeRoutes.addAll(routes);
    // Drop routes to devices that no longer exist, such as the old demo
    // devices; notifyListeners() below saves the cleaned routes.
    final knownIds = {
      ...sources.map((d) => d.id),
      ...destinationsByLocation.values.expand((d) => d).map((d) => d.id),
    };
    activeRoutes.removeWhere(
      (dest, src) =>
          !knownIds.contains(dest) || (src != null && !knownIds.contains(src)),
    );

    isLoaded = true;
    notifyListeners();
  }

  // ── Save helpers ───────────────────────────────────────────────────────────

  Future<void> _persistRoutes() async {
    await DatabaseService.instance.saveActiveRoutes(activeRoutes);
  }

  // ── Overridden notifyListeners — persists routes on every change ───────────

  @override
  void notifyListeners() {
    stateVersionNotifier.value++;
    super.notifyListeners();
    _persistRoutes();
  }

  // ── Device Adoption — saves to DB immediately ──────────────────────────────

  Future<void> adoptDevice(
    String id,
    String name,
    String ip,
    DeviceType type, {
    String? previewUrl,
    String? streamUrl,
    String? channel,
  }) async {
    final newDevice = Device(
      id: id,
      name: name,
      ip: ip,
      type: type,
      status: DeviceStatus.online,
      location: 'Unassigned',
      tags: ['Newly Adopted'],
      previewUrl: previewUrl,
      streamUrl: streamUrl,
      channel: type == DeviceType.tx ? channel : null,
    );

    if (type == DeviceType.tx) {
      if (!sources.any((s) => s.id == id)) {
        sources.add(newDevice);
      }
    } else {
      const location = 'Unassigned';
      destinationsByLocation.putIfAbsent(location, () => []);
      if (!destinationsByLocation[location]!.any((d) => d.id == id)) {
        destinationsByLocation[location]!.add(newDevice);
      }
    }

    await DatabaseService.instance.saveAdoptedDevice(newDevice);
    lastAdoptedDeviceId = id;
    notifyListeners();
  }

  // ── Controller device list ─────────────────────────────────────────────

  /// Controller device id → name, from the last device list.
  final Map<String, String> controllerDeviceNames = {};

  DateTime? _lastDeviceRefresh;
  Future<void>? _deviceRefresh;

  /// Reloads the controller's device list and applies its preview/stream
  /// URLs. Runs on screen open, periodically, and after any 404, because
  /// device ids (and so the URLs) change when the controller restarts.
  /// Skipped while a reload is running or within [minInterval] of the last
  /// one, so many tiles hitting 404 at once cause a single reload.
  Future<void> refreshDevices({
    Duration minInterval = const Duration(seconds: 3),
  }) {
    if (!ApiConfig.isConfigured) return Future.value();
    final running = _deviceRefresh;
    if (running != null) return running;
    final last = _lastDeviceRefresh;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return Future.value();
    }
    _lastDeviceRefresh = DateTime.now();
    return _deviceRefresh = DeviceApiService.fetchDevices()
        .then((found) {
          if (found != null) applyControllerDevices(found);
        })
        .whenComplete(() => _deviceRefresh = null);
  }

  /// Copies online status and preview/stream URLs from a controller device
  /// list onto the matching adopted devices (the adopted id is the MAC
  /// without colons),
  /// and takes each display's current source from the controller when it
  /// reports one.
  void applyControllerDevices(List<DiscoveredDevice> found) {
    // Names of every box the controller knows, adopted or not, so snapshots
    // can show them.
    controllerDeviceNames
      ..clear()
      ..addAll({
        for (final d in found)
          if (d.controllerId != null) d.controllerId!: d.name,
      });
    final byId = {for (final d in found) d.mac.replaceAll(':', ''): d};
    var changed = false;
    for (final device in [
      ...sources,
      ...destinationsByLocation.values.expand((d) => d),
    ]) {
      final match = byId[device.id];
      if (match == null) continue;
      if (device.controllerId != match.controllerId) {
        device.controllerId = match.controllerId;
        changed = true;
      }
      final status =
          match.signal > 0 ? DeviceStatus.online : DeviceStatus.offline;
      if (device.status != status) {
        device.status = status;
        changed = true;
      }
      if (device.previewUrl != match.previewUrl ||
          device.streamUrl != match.streamUrl) {
        device.previewUrl = match.previewUrl;
        device.streamUrl = match.streamUrl;
        changed = true;
      }
      if (device.type == DeviceType.tx && device.channel != match.channel) {
        device.channel = match.channel;
        changed = true;
      }
      if (device.type != DeviceType.tx &&
          device.currentTxIp != match.currentTxIp) {
        device.currentTxIp = match.currentTxIp;
        changed = true;
      }
      // A null current_tx_ip means the controller doesn't know, so the
      // route set from this app stays.
      final txIp = match.currentTxIp;
      if (device.type != DeviceType.tx && txIp != null) {
        final source = sources.where((s) => s.ip == txIp).firstOrNull;
        if (source != null && activeRoutes[device.id] != source.id) {
          activeRoutes[device.id] = source.id;
          changed = true;
        }
      }
    }
    if (changed) notifyListeners();
  }

  // ── Device Removal — deletes from DB immediately ───────────────────────────

  Future<void> removeDevice(String deviceId, String location) async {
    sources.removeWhere((d) => d.id == deviceId);
    destinationsByLocation[location]?.removeWhere((d) => d.id == deviceId);
    if (destinationsByLocation[location]?.isEmpty ?? false) {
      destinationsByLocation.remove(location);
    }
    // Forget routes to or from it; notifyListeners() saves the change.
    activeRoutes.remove(deviceId);
    activeRoutes.removeWhere((_, sourceId) => sourceId == deviceId);
    await DatabaseService.instance.deleteAdoptedDevice(deviceId);
    notifyListeners();
  }

  // ── Snapshots — stored on the controller ──────────────────────────────────

  // Rebuilds listeners without re-saving routes.
  void _refreshListeners() {
    stateVersionNotifier.value++;
    super.notifyListeners();
  }

  /// Reloads the controller's snapshots. Failures land in [snapshotsError].
  Future<void> loadSnapshots() async {
    if (!ApiConfig.isConfigured) return;
    snapshotsLoading = true;
    _refreshListeners();
    try {
      snapshots = await SnapshotService.list();
      snapshotsError = null;
    } on ControllerApiException catch (e) {
      snapshotsError = e;
    } finally {
      snapshotsLoading = false;
      _refreshListeners();
    }
  }

  /// What [displays] show right now, as controller ids. Displays without a
  /// source, or not yet matched to the controller's list, are left out.
  List<SnapshotRoute> currentSnapshotRoutes(Iterable<Device> displays) {
    final sourcesById = {for (final s in sources) s.id: s};
    return [
      for (final display in displays)
        if (display.controllerId != null &&
            sourcesById[activeRoutes[display.id]]?.controllerId != null)
          SnapshotRoute(
            rxId: display.controllerId!,
            txId: sourcesById[activeRoutes[display.id]]!.controllerId!,
          ),
    ];
  }

  /// These throw [ControllerApiException] with a message to show the user.
  Future<void> createSnapshot({
    required String name,
    required String scope,
    required List<SnapshotRoute> routes,
  }) async {
    await SnapshotService.create(name: name, scope: scope, routes: routes);
    await loadSnapshots();
  }

  Future<void> updateSnapshot(
    String id, {
    required String name,
    required String scope,
    required List<SnapshotRoute> routes,
  }) async {
    await SnapshotService.update(id, name: name, scope: scope, routes: routes);
    await loadSnapshots();
  }

  Future<void> deleteSnapshot(String id) async {
    await SnapshotService.delete(id);
    await loadSnapshots();
  }
}
