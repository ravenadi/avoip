import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:authenticav/services/av_command_service.dart';

void main() {
  group('acked', () {
    test('needs success true in the body, not just HTTP 200', () {
      // What the controller returns when the box didn't respond.
      expect(
        AVCommandService.acked(
          http.Response(
            '{"success":false,"ack":"ConnectError: All connection attempts failed","duration_ms":30}',
            200,
          ),
        ),
        isFalse,
      );
      expect(
        AVCommandService.acked(
          http.Response('{"success":true,"ack":"","duration_ms":120}', 200),
        ),
        isTrue,
      );
    });

    test('fails on error statuses and unreadable bodies', () {
      expect(AVCommandService.acked(http.Response('{"success":true}', 500)), isFalse);
      expect(AVCommandService.acked(http.Response('not json', 200)), isFalse);
    });
  });

  group('failedReceivers', () {
    const rxIps = {'192.168.29.200', '192.168.29.213'};

    test('returns only the receivers the controller did not confirm', () {
      final response = http.Response('''{
        "results": [
          {"success": true, "ack": "", "duration_ms": 90, "device_ip": "192.168.29.200", "tx_ip": "192.168.29.187"},
          {"success": false, "ack": "ConnectError", "duration_ms": 30, "device_ip": "192.168.29.213", "tx_ip": "192.168.29.187"}
        ],
        "succeeded": 1,
        "failed": 1
      }''', 200);
      expect(AVCommandService.failedReceivers(rxIps, response), {'192.168.29.213'});
    });

    test('counts receivers missing from the results as failed', () {
      final response = http.Response(
        '{"results": [{"success": true, "device_ip": "192.168.29.200"}], "succeeded": 1, "failed": 0}',
        200,
      );
      expect(AVCommandService.failedReceivers(rxIps, response), {'192.168.29.213'});
    });

    test('treats a failed request as all receivers failing', () {
      expect(
        AVCommandService.failedReceivers(rxIps, http.Response('{"detail":"bad"}', 422)),
        rxIps,
      );
    });
  });
}
