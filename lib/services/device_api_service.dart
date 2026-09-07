import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/device_model.dart';
import '../modules/discovery_module.dart';

/// Fetches the live list of adopted/known AV devices from the backend
/// device registry API, e.g.:
///   GET {ApiConfig.baseUrl}/api/v1/devices
///   -> [{"id","ip","mac","hostname","device_type","status","last_seen"}, ...]
class DeviceApiService {
  static const int _timeoutMs = 8000;

  static String _formatMac(String raw) {
    final hex = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (hex.length != 12) return raw;
    final pairs = <String>[];
    for (int i = 0; i < 12; i += 2) {
      pairs.add(hex.substring(i, i + 2));
    }
    return pairs.join(':');
  }

  /// Fetches devices from the API and maps them into [DiscoveredDevice]s
  /// for display in the Discovery screen. Returns an empty list on failure.
  static Future<List<DiscoveredDevice>> fetchDevices({
    void Function(String status)? onStatus,
  }) async {
    try {
      onStatus?.call('Contacting device registry...');
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices');
      final response = await http.get(uri).timeout(Duration(milliseconds: _timeoutMs));

      if (response.statusCode != 200) {
        onStatus?.call('Server returned ${response.statusCode}.');
        return [];
      }

      final decoded = jsonDecode(response.body);
      final list = decoded is List
          ? decoded
          : (decoded is Map && decoded['devices'] is List ? decoded['devices'] as List : const []);

      final devices = <DiscoveredDevice>[];
      for (final item in list) {
        if (item is! Map) continue;
        final ip = (item['ip'] ?? '').toString();
        if (ip.isEmpty) continue;

        final rawMac = (item['mac'] ?? '').toString();
        final mac = rawMac.isEmpty ? 'N/A' : _formatMac(rawMac);
        final hostname = (item['hostname'] ?? '').toString();
        final typeStr = (item['device_type'] ?? '').toString().toLowerCase();
        final status = (item['status'] ?? '').toString().toLowerCase();

        final type = DeviceType.values.firstWhere(
          (t) => t.name == typeStr,
          orElse: () => DeviceType.rx,
        );

        devices.add(DiscoveredDevice(
          name: hostname.isNotEmpty ? hostname : '${type.name.toUpperCase()}-$ip',
          ip: ip,
          mac: mac,
          signal: status == 'online' ? 100 : 0,
          type: type,
        ));
      }

      return devices;
    } catch (e) {
      debugPrint('DeviceApiService: fetchDevices error: $e');
      onStatus?.call('Could not reach device registry.');
      return [];
    }
  }
}
