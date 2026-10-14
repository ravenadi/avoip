enum DeviceStatus { online, offline, pending, warning }

enum DeviceType { tx, rx, cx }

enum ViewMode { largeGrid, compactGrid, highDensity, list }

class Device {
  final String id;
  String name;
  String ip;
  final DeviceType type;
  // Updated from the controller's device list (see AppState.refreshDevices).
  DeviceStatus status;
  String location;
  final List<String> tags;
  // `preview_url` (current JPEG frame) and `stream_url` (live MJPEG) from the
  // controller's device list. Memory only: they contain controller device
  // ids, which change whenever the controller restarts.
  String? previewUrl;
  String? streamUrl;
  // The controller's id for this box, used by the snapshots API. Learned
  // from the device list (matched by MAC, which is this device's [id]).
  String? controllerId;
  // Live, controller-managed TX channel. Not persisted; refreshed from API.
  String? channel;
  // Current controller-reported route from this RX to a TX.
  String? currentTxIp;

  Device({
    required this.id,
    required this.name,
    required this.ip,
    required this.type,
    required this.status,
    required this.location,
    this.tags = const [],
    this.previewUrl,
    this.streamUrl,
    this.channel,
    this.currentTxIp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'type': type.name,
    'status': status.name,
    'location': location,
  };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    name: json['name'] as String,
    ip: json['ip'] as String,
    type: DeviceType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => DeviceType.rx,
    ),
    status: DeviceStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => DeviceStatus.online,
    ),
    location: json['location'] as String? ?? 'Unassigned',
  );
}
