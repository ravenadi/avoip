import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'controller_api.dart';

export 'controller_api.dart' show ControllerApiException;

/// One screen (Rx) and the source (Tx) it shows, by controller device id.
class SnapshotRoute {
  final String rxId;
  final String txId;
  const SnapshotRoute({required this.rxId, required this.txId});

  Map<String, String> toJson() => {'rx_id': rxId, 'tx_id': txId};
}

/// A routing preset stored on the controller. Touch panels recall the same
/// snapshot with `POST /api/v1/snapshots/{id}/recall`.
class ControllerSnapshot {
  final String id;
  final String name;

  /// "global" (all screens) or "exclusive" (selected screens only).
  final String scope;
  final List<SnapshotRoute> routes;
  final DateTime? createdAt;

  const ControllerSnapshot({
    required this.id,
    required this.name,
    required this.scope,
    required this.routes,
    this.createdAt,
  });

  bool get isGlobal => scope == 'global';
}

/// What happened to one screen during a recall.
class RecallResult {
  final String rxId;
  final String txId;
  final bool success;

  /// Why it was skipped (e.g. "rx_not_found"); null when it was attempted.
  final String? skipReason;

  const RecallResult({
    required this.rxId,
    required this.txId,
    required this.success,
    this.skipReason,
  });
}

/// The controller's snapshots API:
///   GET    /api/v1/snapshots               list
///   POST   /api/v1/snapshots               save   → 201
///   PUT    /api/v1/snapshots/{id}          edit (id stays the same)
///   DELETE /api/v1/snapshots/{id}          → 204
///   POST   /api/v1/snapshots/{id}/recall   apply
/// Save/edit body: {"name", "scope", "routes": [{"rx_id", "tx_id"}]}.
/// A 422 explains in `detail` why routes were rejected.
class SnapshotService {
  static const Map<String, String> _headers = {
    'accept': 'application/json',
    'Content-Type': 'application/json',
  };
  static const Duration _timeout = Duration(seconds: 10);
  // Recall switches every screen in the snapshot, so allow longer.
  static const Duration _recallTimeout = Duration(seconds: 30);

  static Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v1/snapshots$path');

  static Future<List<ControllerSnapshot>> list() async {
    final response = await _send(() => http.get(_uri(''), headers: _headers));
    return parseList(response.body);
  }

  static Future<void> create({
    required String name,
    required String scope,
    required List<SnapshotRoute> routes,
  }) async {
    await _send(
      () => http.post(
        _uri(''),
        headers: _headers,
        body: _body(name, scope, routes),
      ),
    );
  }

  static Future<void> update(
    String id, {
    required String name,
    required String scope,
    required List<SnapshotRoute> routes,
  }) async {
    await _send(
      () => http.put(
        _uri('/${Uri.encodeComponent(id)}'),
        headers: _headers,
        body: _body(name, scope, routes),
      ),
    );
  }

  static Future<void> delete(String id) async {
    await _send(
      () => http.delete(_uri('/${Uri.encodeComponent(id)}'), headers: _headers),
    );
  }

  static Future<List<RecallResult>> recall(String id) async {
    final response = await _send(
      () => http.post(
        _uri('/${Uri.encodeComponent(id)}/recall'),
        headers: _headers,
      ),
      timeout: _recallTimeout,
    );
    return parseRecall(response.body);
  }

  /// The URL integrators call from a touch panel to recall [id].
  static String recallUrl(String id) =>
      _uri('/${Uri.encodeComponent(id)}/recall').toString();

  static String _body(String name, String scope, List<SnapshotRoute> routes) =>
      jsonEncode({
        'name': name,
        'scope': scope,
        'routes': [for (final r in routes) r.toJson()],
      });

  static Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Duration timeout = _timeout,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } catch (e) {
      debugPrint('SnapshotService: $e');
      throw ControllerApiException(
        "Couldn't reach the controller at ${ApiConfig.ip}.",
      );
    }
    debugPrint(
      'SnapshotService: ${response.request?.method} ${response.request?.url} '
      '← ${response.statusCode} ${response.body}',
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw ControllerApiException(
      errorMessage(response.statusCode, response.body),
      statusCode: response.statusCode,
    );
  }

  /// A readable message from an error response's `detail`.
  @visibleForTesting
  static String errorMessage(int statusCode, String body) =>
      ControllerApiException.messageFor(statusCode, body, feature: 'snapshots');

  @visibleForTesting
  static List<ControllerSnapshot> parseList(String body) {
    final decoded = jsonDecode(body);
    final items =
        decoded is List
            ? decoded
            : (decoded is Map && decoded['snapshots'] is List
                ? decoded['snapshots'] as List
                : const []);
    return [
      for (final item in items)
        if (item is Map) _parseSnapshot(item),
    ].whereType<ControllerSnapshot>().toList();
  }

  static ControllerSnapshot? _parseSnapshot(Map item) {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final rawRoutes = item['routes'];
    return ControllerSnapshot(
      id: id,
      name: (item['name'] ?? '').toString(),
      scope: (item['scope'] ?? 'exclusive').toString(),
      routes: [
        if (rawRoutes is List)
          for (final r in rawRoutes)
            if (r is Map && r['rx_id'] != null && r['tx_id'] != null)
              SnapshotRoute(
                rxId: r['rx_id'].toString(),
                txId: r['tx_id'].toString(),
              ),
      ],
      createdAt: DateTime.tryParse((item['created_at'] ?? '').toString()),
    );
  }

  @visibleForTesting
  static List<RecallResult> parseRecall(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final results = decoded['results'];
    final skipped = decoded['skipped'];
    return [
      if (results is List)
        for (final r in results)
          if (r is Map)
            RecallResult(
              rxId: (r['rx_id'] ?? '').toString(),
              txId: (r['tx_id'] ?? '').toString(),
              success: r['success'] == true,
            ),
      if (skipped is List)
        for (final r in skipped)
          if (r is Map)
            RecallResult(
              rxId: (r['rx_id'] ?? '').toString(),
              txId: (r['tx_id'] ?? '').toString(),
              success: false,
              skipReason: (r['reason'] ?? 'skipped').toString(),
            ),
    ];
  }
}
