import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/config/api_config.dart';
import 'package:authenticav/services/unit_status_service.dart';

void main() {
  test('reads the documented status fields', () {
    final units = UnitStatusService.parseList(jsonEncode([
      {
        'id': 'rx-a', 'ip': '192.168.29.213', 'device_type': 'rx', 'reachable': true,
        'video_detected': true, 'monitor_connected': true,
        'source_resolution': '1920x1080', 'source_refresh_hz': 60, 'signal_type': 'DVI',
        'output_resolution': '1680x1050', 'output_refresh_hz': 60,
        'firmware_version': 'A9.19.9', 'firmware_build': '5346',
      },
      // A box that doesn't answer: only the basics come back.
      {'id': 'tx-a', 'ip': '192.168.29.187', 'device_type': 'tx', 'reachable': false},
    ]));
    final rx = units[0];
    expect(rx.isTx, isFalse);
    expect(rx.reachable, isTrue);
    expect(rx.monitorConnected, isTrue);
    expect(rx.videoDetected, isTrue);
    expect(rx.sourceResolution, '1920x1080');
    expect(rx.sourceRefreshHz, 60);
    expect(rx.outputResolution, '1680x1050');
    expect(rx.signalType, 'DVI');
    expect(rx.firmwareVersion, 'A9.19.9');
    expect(rx.firmwareBuild, '5346');
    final tx = units[1];
    expect(tx.isTx, isTrue);
    expect(tx.reachable, isFalse);
    expect(tx.videoDetected, isNull);
    expect(tx.firmwareVersion, isNull);
  });

  group('against a fake controller', () {
    late HttpServer server;
    late int status;
    late Object body;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ApiConfig.useForTesting('127.0.0.1', testPort: server.port);
      server.listen((req) async {
        expect(req.uri.path, '/api/v1/devices/status');
        req.response.statusCode = status;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('fetches all boxes', () async {
      status = 200;
      body = [
        {'id': 'rx-a', 'ip': '10.0.0.2', 'device_type': 'rx', 'reachable': true},
      ];
      final units = await UnitStatusService.fetchAll();
      expect(units.single.id, 'rx-a');
    });

    test('an older controller is reported as needing an update', () async {
      status = 404;
      body = {'detail': 'Not Found'};
      await expectLater(
        UnitStatusService.fetchAll(),
        throwsA(isA<ControllerApiException>()
            .having((e) => e.unsupported, 'unsupported', isTrue)
            .having((e) => e.message, 'message', contains('unit status'))),
      );
    });
  });
}
