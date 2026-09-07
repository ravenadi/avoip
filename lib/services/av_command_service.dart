import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

/// Sends AV routing commands to the backend device registry API.
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/set
///   Body: { "device_ip": "`receiver ip`", "tx_ip": "`transmitter ip`" }
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/set/batch
///   Body: { "items": [{ "device_ip": "...", "tx_ip": "..." }, ...] }
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/stop
///   Body: { "device_ip": "`receiver ip`" }
class AVCommandService {
  static const Map<String, String> _headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
  };

  static Future<http.Response> _post(String path, Map<String, dynamic> body) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final encoded = jsonEncode(body);
    debugPrint('[AVCommandService] POST $uri  body=$encoded');
    return http
        .post(uri, headers: _headers, body: encoded)
        .timeout(const Duration(seconds: 8));
  }

  /// Routes video from a transmitter to a single receiver.
  static Future<bool> routeVideo({
    required String txIp,
    required String rxIp,
  }) async {
    try {
      final response = await _post('/api/v1/commands/set', {
        'device_ip': rxIp,
        'tx_ip': txIp,
      });
      debugPrint(
        '[AVCommandService] ← [${response.statusCode}] ${response.body}',
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AVCommandService] FAILED tx_ip=$txIp device_ip=$rxIp: $e');
      return false;
    }
  }

  /// Routes video from a transmitter to many receivers in a single request.
  static Future<bool> routeVideoBatch({
    required String txIp,
    required List<String> rxIps,
  }) async {
    if (rxIps.isEmpty) return true;
    try {
      final items = rxIps
          .map((rxIp) => {'device_ip': rxIp, 'tx_ip': txIp})
          .toList();
      final response = await _post('/api/v1/commands/set/batch', {
        'items': items,
      });
      debugPrint(
        '[AVCommandService] ← [${response.statusCode}] ${response.body}',
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint(
        '[AVCommandService] BATCH FAILED tx_ip=$txIp device_ips=$rxIps: $e',
      );
      return false;
    }
  }

  /// Stops whatever is currently routed to a receiver.
  static Future<bool> stopRoute({required String rxIp}) async {
    try {
      final response = await _post('/api/v1/commands/stop', {
        'device_ip': rxIp,
      });
      debugPrint(
        '[AVCommandService] ← [${response.statusCode}] ${response.body}',
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AVCommandService] STOP FAILED device_ip=$rxIp: $e');
      return false;
    }
  }
}
