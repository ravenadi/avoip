import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class Sc1WifiNetwork {
  final String ssid;
  final int signal;
  final bool secure;
  const Sc1WifiNetwork(this.ssid, this.signal, this.secure);
}

class Sc1WifiStatus {
  final String state;
  final String? ssid;
  final String? ip;
  final String? error;
  const Sc1WifiStatus(this.state, this.ssid, this.ip, this.error);
}

class Sc1BleWriteException implements Exception {
  final int? code;
  final Object original;
  final Sc1WifiStatus? status;
  final Map<String, dynamic>? info;
  const Sc1BleWriteException(this.code, this.original, this.status, this.info);
}

/// BLE client for the SC-1 provisioning contract. Credentials are encoded and
/// written directly; this service never retains them.
class Sc1BleSetup {
  static const serviceId = '4a7f0000-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const infoId = '4a7f0001-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const networksId = '4a7f0002-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const credentialsId = '4a7f0003-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const statusId = '4a7f0004-1c2b-4d3e-8f5a-6b7c8d9e0f10';
  static const setupCodeId = '4a7f0005-1c2b-4d3e-8f5a-6b7c8d9e0f10';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _info, _networks, _credentials, _status, _setupCode;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  final _devices = <String, ScanResult>{};
  Map<String, dynamic>? info;
  bool _codeAccepted = false;
  final statusEvents = StreamController<Sc1WifiStatus>.broadcast();

  List<ScanResult> get devices => _devices.values.toList();
  Stream<Sc1WifiStatus> get statuses => statusEvents.stream;

  Future<void> scan({Duration timeout = const Duration(seconds: 15)}) async {
    _devices.clear();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName;
        if (name.startsWith('Authentic SC-1 ')) {
          _devices[result.device.remoteId.str] = result;
        }
      }
    });
    await FlutterBluePlus.startScan(
      withServices: [Guid(serviceId)],
      timeout: timeout,
      androidUsesFineLocation: Platform.isAndroid,
    );
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> connect(ScanResult result) async {
    await disconnect();
    _device = result.device;
    await _device!.connect(
      license: License.commercial,
      timeout: const Duration(seconds: 15),
      mtu: null,
    );
    if (Platform.isAndroid) {
      try {
        await _device!.requestMtu(512);
      } catch (_) {
        /* device may negotiate a smaller MTU */
      }
    } else {
      // Let iOS negotiate its preferred MTU during connection.
    }
    final services = await _device!.discoverServices();
    final service =
        services.where((s) => s.uuid == Guid(serviceId)).firstOrNull;
    if (service == null) throw StateError('SC-1 setup service was not found.');
    BluetoothCharacteristic get(String id) =>
        service.characteristics.where((c) => c.uuid == Guid(id)).firstOrNull ??
        (throw StateError('SC-1 setup characteristic is missing.'));
    _info = get(infoId);
    _networks = get(networksId);
    _credentials = get(credentialsId);
    _status = get(statusId);
    _setupCode =
        service.characteristics
            .where((c) => c.uuid == Guid(setupCodeId))
            .firstOrNull;
    info = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(await _info!.read())) as Map,
    );
    _codeAccepted = info?['code_required'] == false;
    _connectionSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        statusEvents.add(const Sc1WifiStatus('disconnected', null, null, null));
      }
    });
  }

  Future<List<Sc1WifiNetwork>> readNetworks() async {
    final json =
        jsonDecode(utf8.decode(await _networks!.read(timeout: 25))) as List;
    return json
        .map(
          (e) => Sc1WifiNetwork(
            e['ssid'] as String,
            (e['signal'] as num).toInt(),
            e['secure'] as bool,
          ),
        )
        .toList();
  }

  Future<Sc1WifiStatus> readStatus() async =>
      _parseStatus(await _status!.read());

  Future<void> subscribeStatus() async {
    if (_statusSub != null) return;
    _statusSub = _status!.onValueReceived.listen((value) {
      if (value.isNotEmpty) statusEvents.add(_parseStatus(value));
    });
    try {
      await _status!.setNotifyValue(true);
    } catch (_) {
      await _statusSub?.cancel();
      _statusSub = null;
      rethrow;
    }
  }

  bool get supportsContractVersion {
    final version = info?['version'];
    if (version is! String) return false;
    final parsed = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?$').firstMatch(version);
    if (parsed == null) return false;
    final major = int.parse(parsed.group(1)!);
    final minor = int.parse(parsed.group(2)!);
    // This app implements contract 1.0. Permit older contract versions, but
    // never send credentials to a newer major or minor contract.
    return major < 1 || (major == 1 && minor <= 0);
  }

  bool get codeAccepted => _codeAccepted;

  Future<void> writeSetupCode(String code) async {
    try {
      await _setupCode!.write(
        utf8.encode(jsonEncode({'code': code})),
        withoutResponse: false,
      );
      _codeAccepted = true;
      return;
    } catch (error) {
      final diagnostic = await _readDiagnostic();
      throw Sc1BleWriteException(
        _attCode(error),
        error,
        diagnostic.$1,
        diagnostic.$2,
      );
    }
  }

  Future<(Sc1WifiStatus?, Map<String, dynamic>?)> _readDiagnostic() async {
    Sc1WifiStatus? status;
    Map<String, dynamic>? latestInfo;
    try {
      status = await readStatus();
    } catch (_) {}
    try {
      latestInfo = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(await _info!.read())) as Map,
      );
      info = latestInfo;
    } catch (_) {}
    return (status, latestInfo);
  }

  int? _attCode(Object error) =>
      error is FlutterBluePlusException ? error.code : null;

  Future<void> provision(String ssid, String password) async {
    if (!supportsContractVersion)
      throw StateError('Unsupported SC-1 contract version.');
    if (!_codeAccepted) throw StateError('The SC-1 setup code is required.');
    await subscribeStatus();
    final payload = utf8.encode(
      jsonEncode({'ssid': ssid, 'password': password}),
    );
    password = '';
    try {
      await _credentials!.write(
        payload,
        withoutResponse: false,
        allowLongWrite: true,
      );
    } catch (error) {
      final diagnostic = await _readDiagnostic();
      throw Sc1BleWriteException(
        _attCode(error),
        error,
        diagnostic.$1,
        diagnostic.$2,
      );
    }
  }

  Sc1WifiStatus _parseStatus(List<int> value) {
    final map = jsonDecode(utf8.decode(value)) as Map;
    return Sc1WifiStatus(
      map['state'] as String,
      map['ssid'] as String?,
      map['ip'] as String?,
      map['error'] as String?,
    );
  }

  Future<void> disconnect() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await disconnect();
    await statusEvents.close();
  }
}
