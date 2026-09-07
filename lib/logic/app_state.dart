import 'package:flutter/foundation.dart';
import '../models/device_model.dart';
import '../services/database_service.dart';

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

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._internal();
  AppState._internal() {
    initializeSampleData();
  }

  bool isLoaded = false;

  // Active Device Registries
  final List<Device> sources = [];
  final Map<String, List<Device>> destinationsByLocation = {};

  // Security/RBAC Authentication Registry
  final List<UserAccount> users = [];

  // Active Matrix Routing Paths (Destination ID -> Source ID)
  final Map<String, String?> activeRoutes = {};

  // Saved routing configurations
  final List<Map<String, dynamic>> savedSnapshots = [];

  // Global Notifiers for listeners
  final ValueNotifier<int> stateVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> tabIndexNotifier = ValueNotifier<int>(0);

  // Track the most recently adopted device to auto-focus in Configuration
  String? lastAdoptedDeviceId;

  // Mock Firmware Repository
  final List<Map<String, dynamic>> firmwareDownloads = [
    {'version': 'v2.4.1', 'status': 'Available', 'size': '45MB'},
    {'version': 'v2.3.9', 'status': 'Installed', 'size': '42MB'},
  ];

  String firmwareDeploymentStatus = 'Idle';

  void initializeSampleData() {
    if (users.isNotEmpty) return;
    users.addAll([
      UserAccount(id: 'u1', username: 'admin', password: '123', role: 'Admin'),
      UserAccount(id: 'u2', username: 'operator', password: '123', role: 'User'),
    ]);

    if (sources.isEmpty) {
      sources.addAll([
        Device(id: 'demo_tx_1', name: 'Main Camera', ip: '192.168.1.101', type: DeviceType.tx, status: DeviceStatus.online, location: 'Unassigned', tags: ['Demo'], videoUrl: _demoVideos[0], previewUrl: 'hdmi.png'),
        Device(id: 'demo_tx_2', name: 'Presenter Laptop', ip: '192.168.1.102', type: DeviceType.tx, status: DeviceStatus.online, location: 'Unassigned', tags: ['Demo'], videoUrl: _demoVideos[1], previewUrl: 'hdmi.png'),
        Device(id: 'demo_tx_3', name: 'Document Camera', ip: '192.168.1.103', type: DeviceType.tx, status: DeviceStatus.online, location: 'Unassigned', tags: ['Demo'], videoUrl: _demoVideos[2], previewUrl: 'hdmi.png'),
        Device(id: 'demo_tx_4', name: 'Media Server', ip: '192.168.1.104', type: DeviceType.tx, status: DeviceStatus.online, location: 'Unassigned', tags: ['Demo'], videoUrl: _demoVideos[3], previewUrl: 'hdmi.png'),
        Device(id: 'demo_tx_5', name: 'Remote Feed', ip: '192.168.1.105', type: DeviceType.tx, status: DeviceStatus.online, location: 'Unassigned', tags: ['Demo'], videoUrl: _demoVideos[4], previewUrl: 'hdmi.png'),
        Device(id: 'demo_tx_6', name: 'Evidence Display', ip: '192.168.1.106', type: DeviceType.tx, status: DeviceStatus.online, location: 'Unassigned', tags: ['Demo'], videoUrl: _demoVideos[5], previewUrl: 'hdmi.png'),
      ]);
    }

    if (destinationsByLocation.isEmpty) {
      final demoDestinations = {
        'Courtroom A': [
          Device(id: 'demo_rx_1', name: 'Main Display', ip: '192.168.1.201', type: DeviceType.rx, status: DeviceStatus.online, location: 'Courtroom A', tags: ['Demo']),
          Device(id: 'demo_rx_2', name: 'Side Display', ip: '192.168.1.202', type: DeviceType.rx, status: DeviceStatus.online, location: 'Courtroom A', tags: ['Demo']),
        ],
        'Courtroom B': [
          Device(id: 'demo_rx_3', name: 'Main Display', ip: '192.168.1.203', type: DeviceType.rx, status: DeviceStatus.online, location: 'Courtroom B', tags: ['Demo']),
          Device(id: 'demo_rx_4', name: 'Witness Screen', ip: '192.168.1.204', type: DeviceType.rx, status: DeviceStatus.online, location: 'Courtroom B', tags: ['Demo']),
        ],
        'Conference Room': [
          Device(id: 'demo_rx_5', name: 'Projector', ip: '192.168.1.205', type: DeviceType.rx, status: DeviceStatus.online, location: 'Conference Room', tags: ['Demo']),
          Device(id: 'demo_rx_6', name: 'Side Monitor', ip: '192.168.1.206', type: DeviceType.rx, status: DeviceStatus.online, location: 'Conference Room', tags: ['Demo']),
        ],
        'Lobby': [
          Device(id: 'demo_rx_7', name: 'Reception Display', ip: '192.168.1.207', type: DeviceType.rx, status: DeviceStatus.online, location: 'Lobby', tags: ['Demo']),
        ],
      };
      for (final entry in demoDestinations.entries) {
        destinationsByLocation[entry.key] = entry.value;
      }
    }
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

    // Load snapshots
    final snapshots = await db.loadSnapshots();
    savedSnapshots.addAll(snapshots);

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

  void clearAllRoutes() {
    activeRoutes.clear();
    notifyListeners();
  }

  void loadSnapshotRoutes(Map<String, String?> snapshotMapping) {
    activeRoutes.clear();
    activeRoutes.addAll(snapshotMapping);
    notifyListeners();
  }

  void toggleWink(String deviceId) {
    final device = [...sources, ...destinationsByLocation.values.expand((d) => d)]
        .firstWhere((d) => d.id == deviceId);
    device.isWinking = !device.isWinking;
    notifyListeners();

    if (device.isWinking) {
      Future.delayed(const Duration(seconds: 10), () {
        device.isWinking = false;
        notifyListeners();
      });
    }
  }

  // ── Device Adoption — saves to DB immediately ──────────────────────────────

  static const _demoVideos = [
    'assets/videos/demo_video_1.mp4',
    'assets/videos/demo_video_2.mp4',
    'assets/videos/demo_video_3.mp4',
    'assets/videos/demo_video_4.mp4',
    'assets/videos/demo_video_5.mp4',
    'assets/videos/demo_video_6.mp4',
  ];

  Future<void> adoptDevice(String id, String name, String ip, DeviceType type) async {
    // Assign a unique demo video per TX device (cycles through 6 available videos)
    String? videoUrl;
    if (type == DeviceType.tx) {
      videoUrl = _demoVideos[sources.length % _demoVideos.length];
    }

    final newDevice = Device(
      id: id,
      name: name,
      ip: ip,
      type: type,
      status: DeviceStatus.online,
      location: 'Unassigned',
      tags: ['Newly Adopted'],
      previewUrl: type == DeviceType.tx ? 'hdmi.png' : 'monitor.png',
      videoUrl: videoUrl,
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

  // ── Device Removal — deletes from DB immediately ───────────────────────────

  Future<void> removeDevice(String deviceId, String location) async {
    sources.removeWhere((d) => d.id == deviceId);
    destinationsByLocation[location]?.removeWhere((d) => d.id == deviceId);
    if (destinationsByLocation[location]?.isEmpty ?? false) {
      destinationsByLocation.remove(location);
    }
    await DatabaseService.instance.deleteAdoptedDevice(deviceId);
    notifyListeners();
  }

  // ── Snapshots — saves to DB immediately ───────────────────────────────────

  Future<void> addSnapshot(Map<String, dynamic> snapshot) async {
    await DatabaseService.instance.saveSnapshot(snapshot);
    // Reload from DB to get the real auto-incremented id
    final snapshots = await DatabaseService.instance.loadSnapshots();
    savedSnapshots
      ..clear()
      ..addAll(snapshots);
    stateVersionNotifier.value++;
    super.notifyListeners();
  }

  Future<void> deleteSnapshot(int index) async {
    final snap = savedSnapshots[index];
    final snapId = snap['id'];
    if (snapId != null) {
      await DatabaseService.instance.deleteSnapshot(snapId as int);
    }
    savedSnapshots.removeAt(index);
    stateVersionNotifier.value++;
    super.notifyListeners();
  }

  Future<bool> updateStreamSelection(String deviceId, String streamId) async {
    debugPrint('API CALL: updateStreamSelection(device: $deviceId, stream: $streamId)');
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }
}
