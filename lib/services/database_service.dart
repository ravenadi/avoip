import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/device_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'authenticav.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE discovered_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        ip TEXT NOT NULL UNIQUE,
        mac TEXT NOT NULL,
        signal INTEGER NOT NULL DEFAULT 100,
        type TEXT NOT NULL,
        last_seen INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE adopted_devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'online',
        location TEXT NOT NULL DEFAULT 'Unassigned',
        preview_url TEXT,
        video_url TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE active_routes (
        destination_id TEXT PRIMARY KEY,
        source_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ── Discovered Devices ────────────────────────────────────────────────────

  /// Replaces the saved scan with [devices].
  Future<void> saveDiscoveredDevices(List<Map<String, dynamic>> devices) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    batch.delete('discovered_devices');

    for (final d in devices) {
      batch.insert(
        'discovered_devices',
        {...d, 'last_seen': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> loadDiscoveredDevices() async {
    final db = await database;
    return await db.query('discovered_devices', orderBy: 'last_seen DESC');
  }

  // ── Adopted Devices ───────────────────────────────────────────────────────

  Future<void> saveAdoptedDevice(Device device) async {
    final db = await database;
    await db.insert(
      'adopted_devices',
      {
        'id': device.id,
        'name': device.name,
        'ip': device.ip,
        'type': device.type.name,
        'status': device.status.name,
        'location': device.location,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAdoptedDevice(String deviceId) async {
    final db = await database;
    await db.delete('adopted_devices', where: 'id = ?', whereArgs: [deviceId]);
  }

  Future<List<Device>> loadAdoptedDevices() async {
    final db = await database;
    final rows = await db.query('adopted_devices');
    return rows.map((row) => Device(
      id: row['id'] as String,
      name: row['name'] as String,
      ip: row['ip'] as String,
      type: DeviceType.values.firstWhere((e) => e.name == row['type'], orElse: () => DeviceType.rx),
      status: DeviceStatus.values.firstWhere((e) => e.name == row['status'], orElse: () => DeviceStatus.online),
      location: row['location'] as String? ?? 'Unassigned',
    )).toList();
  }

  // ── Active Routes ─────────────────────────────────────────────────────────

  Future<void> saveActiveRoutes(Map<String, String?> routes) async {
    final db = await database;
    await db.delete('active_routes');
    final batch = db.batch();
    for (final entry in routes.entries) {
      batch.insert('active_routes', {
        'destination_id': entry.key,
        'source_id': entry.value,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, String?>> loadActiveRoutes() async {
    final db = await database;
    final rows = await db.query('active_routes');
    return {for (final r in rows) r['destination_id'] as String: r['source_id'] as String?};
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<String?> loadSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }
}
