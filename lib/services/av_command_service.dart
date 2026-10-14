import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

/// Sends AV routing commands to the controller:
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/set
///   Body: { "device_ip": "`receiver ip`", "tx_ip": "`transmitter ip`" }
///   -> { "success", "ack", "duration_ms" }
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/set/batch
///   Body: { "items": [{ "device_ip": "...", "tx_ip": "..." }, ...] }  (max 50)
///   -> { "results": [{ "success", "device_ip", "tx_ip", ... }],
///        "succeeded", "failed" }
///
///   POST {ApiConfig.baseUrl}/api/v1/commands/stop
///   Body: { "device_ip": "`receiver ip`" }
///   -> { "success", "ack", "duration_ms" }
///
/// The controller answers 200 even when a box didn't respond, so success
/// is read from the body, not the status code.
class AVCommandService {
  static const Map<String, String> _headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
  };

  // The controller accepts at most this many pairs per batch call.
  static const int _maxBatchItems = 50;

  static Future<http.Response> _post(String path, Map<String, dynamic> body) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final encoded = jsonEncode(body);
    debugPrint('[AVCommandService] POST $uri  body=$encoded');
    return http
        .post(uri, headers: _headers, body: encoded)
        .timeout(const Duration(seconds: 8));
  }

  // True when the call returned 2xx and the box confirmed it.
  @visibleForTesting
  static bool acked(http.Response response) {
    debugPrint(
      '[AVCommandService] ← [${response.statusCode}] ${response.body}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['success'] == true;
    } catch (_) {
      return false;
    }
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
      return acked(response);
    } catch (e) {
      debugPrint('[AVCommandService] FAILED tx_ip=$txIp device_ip=$rxIp: $e');
      return false;
    }
  }

  /// Routes many receivers at once; [txIpByRxIp] maps each receiver to the
  /// transmitter it should show, so different receivers can get different
  /// sources. Returns the receiver IPs that failed (empty when all worked).
  static Future<Set<String>> routeBatch(Map<String, String> txIpByRxIp) async {
    final failed = <String>{};
    final pairs = txIpByRxIp.entries.toList();
    for (var i = 0; i < pairs.length; i += _maxBatchItems) {
      final chunk = pairs.skip(i).take(_maxBatchItems).toList();
      failed.addAll(await _routeChunk(chunk));
    }
    return failed;
  }

  static Future<Set<String>> _routeChunk(
    List<MapEntry<String, String>> pairs,
  ) async {
    final rxIps = pairs.map((p) => p.key).toSet();
    try {
      final response = await _post('/api/v1/commands/set/batch', {
        'items': [
          for (final p in pairs) {'device_ip': p.key, 'tx_ip': p.value},
        ],
      });
      return failedReceivers(rxIps, response);
    } catch (e) {
      debugPrint('[AVCommandService] BATCH FAILED $pairs: $e');
      return rxIps;
    }
  }

  /// The receivers in [rxIps] that a batch [response] didn't confirm.
  @visibleForTesting
  static Set<String> failedReceivers(
    Set<String> rxIps,
    http.Response response,
  ) {
    debugPrint(
      '[AVCommandService] ← [${response.statusCode}] ${response.body}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return rxIps;
    try {
      final decoded = jsonDecode(response.body);
      final results = decoded is Map ? decoded['results'] : null;
      if (results is! List) return rxIps;
      final ok = {
        for (final r in results)
          if (r is Map && r['success'] == true) r['device_ip'].toString(),
      };
      return rxIps.difference(ok);
    } catch (_) {
      return rxIps;
    }
  }

  /// Stops whatever is currently routed to a receiver.
  static Future<bool> stopRoute({required String rxIp}) async {
    try {
      final response = await _post('/api/v1/commands/stop', {
        'device_ip': rxIp,
      });
      return acked(response);
    } catch (e) {
      debugPrint('[AVCommandService] STOP FAILED device_ip=$rxIp: $e');
      return false;
    }
  }
}
