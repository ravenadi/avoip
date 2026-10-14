import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/device_model.dart';
import '../modules/discovery_module.dart';

/// Fetches the live list of AV devices from the controller's registry:
///   GET {ApiConfig.baseUrl}/api/v1/devices
///   -> [{"id","ip","mac","hostname","device_type","status","last_seen",
///        "current_tx_ip","channel","preview_url","stream_url"}, ...]
/// `preview_url` is the current JPEG frame of the box and `stream_url` its
/// live MJPEG stream; both are served by the controller.
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

  static String? _nonEmpty(Object? raw) {
    final value = (raw ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  // Absolute URLs pass through; relative ones resolve against the server.
  static String? _resolveUrl(Object? raw) {
    final url = (raw ?? '').toString().trim();
    if (url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return url;
    return Uri.parse(ApiConfig.baseUrl).resolve(url).toString();
  }

  /// Asks the controller to look for new boxes on the network
  /// (`POST /api/v1/devices/scan` → `{"scanned": 4}`, or 502 with a
  /// `detail`). Returns null on success, otherwise why it failed.
  static Future<String?> triggerScan() async {
    try {
      final response = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/scan'))
          .timeout(const Duration(seconds: 60));
      debugPrint(
        'DeviceApiService: scan → ${response.statusCode} ${response.body}',
      );
      if (response.statusCode >= 200 && response.statusCode < 300) return null;
      try {
        final detail = (jsonDecode(response.body) as Map)['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
      } catch (_) {}
      return 'the controller answered ${response.statusCode}';
    } catch (e) {
      debugPrint('DeviceApiService: scan error: $e');
      return "couldn't reach the controller";
    }
  }

  /// Fetches devices from the API and maps them into [DiscoveredDevice]s.
  /// Returns null if the controller couldn't be reached or answered with an
  /// error, so callers can tell that apart from "no devices".
  /// If the controller can't be reached at all, its new IP is looked up on
  /// the network (DHCP may have changed it) and the request is tried again.
  static Future<List<DiscoveredDevice>?> fetchDevices({
    void Function(String status)? onStatus,
    bool retryOnNewIp = true,
  }) async {
    try {
      onStatus?.call('Contacting device registry...');
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices');
      final response = await http
          .get(uri)
          .timeout(Duration(milliseconds: _timeoutMs));

      if (response.statusCode != 200) {
        onStatus?.call('Server returned ${response.statusCode}.');
        return null;
      }

      return parseDevices(jsonDecode(response.body));
    } on FormatException catch (e) {
      debugPrint('DeviceApiService: bad device list: $e');
      onStatus?.call('The controller sent an unreadable device list.');
      return null;
    } catch (e) {
      debugPrint('DeviceApiService: fetchDevices error: $e');
      if (retryOnNewIp && await ApiConfig.rediscover()) {
        onStatus?.call('Controller moved to ${ApiConfig.ip}. Retrying...');
        return fetchDevices(onStatus: onStatus, retryOnNewIp: false);
      }
      onStatus?.call('Could not reach device registry.');
      return null;
    }
  }

  /// Maps the decoded `/devices` body (a list, or `{"devices": [...]}`)
  /// into [DiscoveredDevice]s, skipping entries without an IP.
  @visibleForTesting
  static List<DiscoveredDevice> parseDevices(Object? decoded) {
    final list =
        decoded is List
            ? decoded
            : (decoded is Map && decoded['devices'] is List
                ? decoded['devices'] as List
                : const []);

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
      final currentTxIp = (item['current_tx_ip'] ?? '').toString().trim();

      final type = DeviceType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => DeviceType.rx,
      );

      devices.add(
        DiscoveredDevice(
          controllerId: _nonEmpty(item['id']),
          name:
              hostname.isNotEmpty ? hostname : '${type.name.toUpperCase()}-$ip',
          ip: ip,
          mac: mac,
          signal: status == 'online' ? 100 : 0,
          type: type,
          previewUrl: _resolveUrl(item['preview_url']),
          streamUrl: _resolveUrl(item['stream_url']),
          currentTxIp: currentTxIp.isEmpty ? null : currentTxIp,
          channel: type == DeviceType.tx ? _nonEmpty(item['channel']) : null,
        ),
      );
    }
    return devices;
  }
}
