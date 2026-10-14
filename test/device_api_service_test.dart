import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/models/device_model.dart';
import 'package:authenticav/services/device_api_service.dart';

void main() {
  test('reads preview_url and stream_url from the controller device list', () {
    // Shape of GET /api/v1/devices on the controller.
    final devices = DeviceApiService.parseDevices(
      jsonDecode('''[
        {
          "id": "7752f413-f5d9-41b0-ab82-087e10c85498",
          "ip": "192.168.29.187",
          "mac": "447CAC010013",
          "hostname": "Auth-VTX-1_447CAC010013",
          "device_type": "tx",
          "status": "online",
          "current_tx_ip": null,
          "preview_url": "http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/preview.jpg",
          "stream_url": "http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/stream"
        },
        {
          "id": "642b504c-9ea4-4967-bc8f-bc8d06134d4c",
          "ip": "192.168.29.200",
          "mac": "447CAC020013",
          "hostname": "Auth-VRX-1_447CAC020013",
          "device_type": "rx",
          "status": "offline",
          "current_tx_ip": "192.168.29.187"
        }
      ]'''),
    );

    expect(devices, hasLength(2));

    final tx = devices[0];
    expect(tx.name, 'Auth-VTX-1_447CAC010013');
    expect(tx.type, DeviceType.tx);
    // Adopted devices use the MAC without colons as their id.
    expect(tx.mac.replaceAll(':', ''), '447CAC010013');
    expect(
      tx.previewUrl,
      'http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/preview.jpg',
    );
    expect(
      tx.streamUrl,
      'http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/stream',
    );

    final rx = devices[1];
    expect(rx.type, DeviceType.rx);
    expect(rx.signal, 0);
    expect(rx.previewUrl, isNull);
    expect(rx.streamUrl, isNull);
    expect(rx.currentTxIp, '192.168.29.187');
    expect(tx.currentTxIp, isNull);
  });

  test('skips entries without an IP and accepts a devices wrapper', () {
    final devices = DeviceApiService.parseDevices({
      'devices': [
        {'ip': '', 'mac': '447CAC030013'},
        {'ip': '192.168.29.201', 'mac': '447CAC040013', 'device_type': 'rx'},
      ],
    });
    expect(devices.map((d) => d.ip), ['192.168.29.201']);
  });
}
