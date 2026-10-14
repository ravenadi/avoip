import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/config/api_config.dart';
import 'package:authenticav/logic/app_state.dart';
import 'package:authenticav/models/device_model.dart';
import 'package:authenticav/services/snapshot_service.dart';

/// A fake controller on 127.0.0.1:8000 speaking the documented snapshots API.
class _FakeController {
  late HttpServer server;
  final requests = <({String method, String path, Object? body})>[];
  int Function(String method, String path)? statusFor;
  Object? Function(String method, String path)? bodyFor;

  Future<void> start() async {
    // Port 0: a free port, so test files can run in parallel.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ApiConfig.useForTesting('127.0.0.1', testPort: server.port);
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      requests.add((
        method: req.method,
        path: req.uri.path,
        body: raw.isEmpty ? null : jsonDecode(raw),
      ));
      final status = statusFor?.call(req.method, req.uri.path) ?? 200;
      req.response.statusCode = status;
      final body = bodyFor?.call(req.method, req.uri.path);
      if (body != null) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
      }
      await req.response.close();
    });
  }
}

void main() {
  late _FakeController controller;

  setUp(() async {
    controller = _FakeController();
    await controller.start();
  });

  tearDown(() async {
    await controller.server.close(force: true);
  });

  test('lists snapshots in the documented shape', () async {
    controller.bodyFor = (m, p) => [
      {
        'id': 'snap-1',
        'name': 'Lobby - laptop',
        'scope': 'exclusive',
        'routes': [
          {'rx_id': 'rx-a', 'tx_id': 'tx-a'},
        ],
        'created_at': '2026-10-09T10:00:00Z',
      },
    ];
    final list = await SnapshotService.list();
    expect(controller.requests.single.path, '/api/v1/snapshots');
    expect(list.single.id, 'snap-1');
    expect(list.single.name, 'Lobby - laptop');
    expect(list.single.isGlobal, isFalse);
    expect(list.single.routes.single.rxId, 'rx-a');
    expect(list.single.routes.single.txId, 'tx-a');
    expect(list.single.createdAt, DateTime.utc(2026, 10, 9, 10));
  });

  test('saves with name, scope and device-id routes', () async {
    controller.statusFor = (m, p) => 201;
    controller.bodyFor = (m, p) => {'id': 'snap-2'};
    await SnapshotService.create(
      name: 'All screens',
      scope: 'global',
      routes: const [SnapshotRoute(rxId: 'rx-a', txId: 'tx-b')],
    );
    final req = controller.requests.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/v1/snapshots');
    expect(req.body, {
      'name': 'All screens',
      'scope': 'global',
      'routes': [
        {'rx_id': 'rx-a', 'tx_id': 'tx-b'},
      ],
    });
  });

  test("shows the controller's 422 reason", () async {
    controller.statusFor = (m, p) => 422;
    controller.bodyFor = (m, p) => {'detail': 'tx-a is a Tx and cannot be a screen'};
    await expectLater(
      SnapshotService.create(name: 'x', scope: 'exclusive', routes: const []),
      throwsA(
        isA<ControllerApiException>().having(
          (e) => e.message,
          'message',
          'tx-a is a Tx and cannot be a screen',
        ),
      ),
    );
    // FastAPI validation errors come as a list.
    expect(
      SnapshotService.errorMessage(
        422,
        jsonEncode({
          'detail': [
            {'loc': ['body', 'name'], 'msg': 'Field required'},
          ],
        }),
      ),
      'Field required',
    );
  });

  test('edits and deletes by id', () async {
    controller.statusFor = (m, p) => m == 'DELETE' ? 204 : 200;
    await SnapshotService.update(
      'snap-1',
      name: 'Renamed',
      scope: 'exclusive',
      routes: const [SnapshotRoute(rxId: 'rx-a', txId: 'tx-a')],
    );
    await SnapshotService.delete('snap-1');
    expect(controller.requests[0].method, 'PUT');
    expect(controller.requests[0].path, '/api/v1/snapshots/snap-1');
    expect((controller.requests[0].body as Map)['name'], 'Renamed');
    expect(controller.requests[1].method, 'DELETE');
    expect(controller.requests[1].path, '/api/v1/snapshots/snap-1');
  });

  test('recall reports each screen, including skipped ones', () async {
    controller.bodyFor = (m, p) => {
      'id': 'snap-1',
      'name': 'Lobby - laptop',
      'results': [
        {'rx_id': 'rx-a', 'tx_id': 'tx-a', 'rx_ip': '10.0.0.2', 'tx_ip': '10.0.0.1', 'success': true, 'ack': 'OK', 'duration_ms': 110},
        {'rx_id': 'rx-b', 'tx_id': 'tx-a', 'rx_ip': '10.0.0.3', 'tx_ip': '10.0.0.1', 'success': false, 'ack': 'timeout', 'duration_ms': 3000},
      ],
      'skipped': [
        {'rx_id': 'rx-c', 'tx_id': 'tx-a', 'reason': 'rx_not_found'},
      ],
      'succeeded': 1,
      'failed': 1,
    };
    final results = await SnapshotService.recall('snap-1');
    expect(controller.requests.single.method, 'POST');
    expect(controller.requests.single.path, '/api/v1/snapshots/snap-1/recall');
    expect(results.map((r) => (r.rxId, r.success, r.skipReason)), [
      ('rx-a', true, null),
      ('rx-b', false, null),
      ('rx-c', false, 'rx_not_found'),
    ]);
    expect(
      SnapshotService.recallUrl('snap-1'),
      'http://127.0.0.1:${controller.server.port}/api/v1/snapshots/snap-1/recall',
    );
  });

  test('an older controller without snapshots is reported as such', () async {
    controller.statusFor = (m, p) => 404;
    controller.bodyFor = (m, p) => {'detail': 'Not Found'};
    await expectLater(
      SnapshotService.list(),
      throwsA(isA<ControllerApiException>().having((e) => e.unsupported, 'unsupported', isTrue)),
    );
  });

  test('an unreachable controller gives a clear message', () async {
    await controller.server.close(force: true);
    await expectLater(
      SnapshotService.list(),
      throwsA(
        isA<ControllerApiException>().having(
          (e) => e.message,
          'message',
          contains("Couldn't reach the controller"),
        ),
      ),
    );
    await controller.start(); // tearDown closes it again
  });

  test('current routing becomes controller-id routes', () {
    final state = AppState.instance;
    Device dev(String id, DeviceType t, String? controllerId) => Device(
      id: id,
      name: id,
      ip: '10.0.0.$id'.length.toString(),
      type: t,
      status: DeviceStatus.online,
      location: 'Unassigned',
    )..controllerId = controllerId;
    final tx = dev('TX1', DeviceType.tx, 'tx-a');
    final rx1 = dev('RX1', DeviceType.rx, 'rx-a');
    final rx2 = dev('RX2', DeviceType.rx, 'rx-b'); // no source
    final rx3 = dev('RX3', DeviceType.rx, null); // not on the controller
    state.sources.add(tx);
    state.activeRoutes['RX1'] = 'TX1';
    state.activeRoutes['RX3'] = 'TX1';
    final routes = state.currentSnapshotRoutes([rx1, rx2, rx3]);
    expect(routes.map((r) => (r.rxId, r.txId)), [('rx-a', 'tx-a')]);
    state.sources.remove(tx);
    state.activeRoutes.clear();
  });
}
