import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'controller_api.dart';

export 'controller_api.dart' show ControllerApiException;

/// Live parameters of one box, read from its console by the controller.
/// Fields are null when the box didn't report them.
class UnitStatus {
  /// Controller device id.
  final String id;
  final String ip;

  /// "tx" (source) or "rx" (screen).
  final String deviceType;
  final bool reachable;
  final bool? videoDetected;
  final bool? monitorConnected;
  final String? sourceResolution;
  final num? sourceRefreshHz;
  final String? signalType;
  final String? outputResolution;
  final num? outputRefreshHz;
  final String? firmwareVersion;
  final String? firmwareBuild;

  const UnitStatus({
    required this.id,
    required this.ip,
    required this.deviceType,
    required this.reachable,
    this.videoDetected,
    this.monitorConnected,
    this.sourceResolution,
    this.sourceRefreshHz,
    this.signalType,
    this.outputResolution,
    this.outputRefreshHz,
    this.firmwareVersion,
    this.firmwareBuild,
  });

  bool get isTx => deviceType == 'tx';

  factory UnitStatus.fromJson(Map json) {
    String? text(String key) {
      final v = json[key]?.toString().trim();
      return v == null || v.isEmpty ? null : v;
    }

    bool? flag(String key) => json[key] is bool ? json[key] as bool : null;
    num? number(String key) => json[key] is num ? json[key] as num : null;

    return UnitStatus(
      id: text('id') ?? '',
      ip: text('ip') ?? '',
      deviceType: (text('device_type') ?? 'rx').toLowerCase(),
      reachable: json['reachable'] == true,
      videoDetected: flag('video_detected'),
      monitorConnected: flag('monitor_connected'),
      sourceResolution: text('source_resolution'),
      sourceRefreshHz: number('source_refresh_hz'),
      signalType: text('signal_type'),
      outputResolution: text('output_resolution'),
      outputRefreshHz: number('output_refresh_hz'),
      firmwareVersion: text('firmware_version'),
      firmwareBuild: text('firmware_build'),
    );
  }
}

/// `GET /api/v1/devices/status`: every box's live status. Reading the
/// boxes takes the controller a few seconds, so call it on screen open or
/// when the user refreshes, not on a timer.
class UnitStatusService {
  static const Duration _timeout = Duration(seconds: 20);

  static Future<List<UnitStatus>> fetchAll() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/status');
    final http.Response response;
    try {
      response = await http
          .get(uri, headers: const {'accept': 'application/json'})
          .timeout(_timeout);
    } catch (e) {
      debugPrint('UnitStatusService: $e');
      throw ControllerApiException(
        "Couldn't reach the controller at ${ApiConfig.ip}.",
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ControllerApiException(
        ControllerApiException.messageFor(
          response.statusCode,
          response.body,
          feature: 'unit status',
        ),
        statusCode: response.statusCode,
      );
    }
    try {
      return parseList(response.body);
    } on FormatException {
      throw const ControllerApiException(
        'The controller sent an unreadable status list.',
      );
    }
  }

  @visibleForTesting
  static List<UnitStatus> parseList(String body) {
    final decoded = jsonDecode(body);
    final items =
        decoded is List
            ? decoded
            : (decoded is Map && decoded['devices'] is List
                ? decoded['devices'] as List
                : const []);
    return [
      for (final item in items)
        if (item is Map) UnitStatus.fromJson(item),
    ].where((s) => s.id.isNotEmpty).toList();
  }
}
