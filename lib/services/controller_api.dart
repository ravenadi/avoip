import 'dart:convert';

/// A controller API call that failed, with a message to show the user.
class ControllerApiException implements Exception {
  final String message;
  final int? statusCode;
  const ControllerApiException(this.message, {this.statusCode});

  /// The controller doesn't have this API yet (older controller software).
  bool get unsupported => statusCode == 404 || statusCode == 405;

  @override
  String toString() => message;

  /// A readable message from an error response. [feature] names what an
  /// older controller is missing, e.g. "snapshots".
  static String messageFor(
    int statusCode,
    String body, {
    required String feature,
  }) {
    if (statusCode == 404 || statusCode == 405) {
      return 'This controller has no $feature yet. Update the controller software.';
    }
    try {
      final detail = (jsonDecode(body) as Map)['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      // FastAPI validation errors: [{"loc": [...], "msg": "..."}]
      if (detail is List && detail.isNotEmpty) {
        return detail
            .map((e) => e is Map ? e['msg']?.toString() ?? '' : e.toString())
            .where((m) => m.isNotEmpty)
            .join('; ');
      }
    } catch (_) {}
    return 'The controller answered $statusCode.';
  }
}
