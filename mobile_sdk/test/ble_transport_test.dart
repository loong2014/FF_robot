import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/src/models/connection_options.dart';
import 'package:mobile_sdk/src/transports/ble_discovered_device.dart';
import 'package:mobile_sdk/src/transports/ble_transport.dart';
import 'package:robot_protocol/robot_protocol.dart';

void main() {
  group('BleTransport', () {
    test('scan falls back to unfiltered scan when service filter finds nothing',
        () async {
      late _FakeBlePlatformAdapter adapter;
      adapter = _FakeBlePlatformAdapter(
        session: _FakeBleConnectionSession(),
        onStartScan: (serviceUuids, timeout) {
          if (serviceUuids.isEmpty) {
            Future<void>.delayed(const Duration(milliseconds: 10), () {
              adapter.emitScanResults(
                const <BleDiscoveredDevice>[
                  BleDiscoveredDevice(
                    id: 'robot-1',
                    name: 'RobotOSLite',
                    rssi: -48,
                  ),
                ],
              );
            });
          }
        },
      );

      final device = await BleTransport.scan(
        withServices: <String>{BleConnectionOptions.defaultServiceUuid},
        timeout: const Duration(milliseconds: 120),
        platform: adapter,
      ).first;

      expect(device.id, 'robot-1');
      expect(
        adapter.scanRequests,
        <List<String>>[
          <String>[BleConnectionOptions.defaultServiceUuid],
          <String>[],
        ],
      );
      expect(adapter.stopScanCalls, greaterThanOrEqualTo(1));
    });

    test('scan keeps service filter when matching result arrives in time',
        () async {
      late _FakeBlePlatformAdapter adapter;
      adapter = _FakeBlePlatformAdapter(
        session: _FakeBleConnectionSession(),
        onStartScan: (serviceUuids, timeout) {
          if (serviceUuids.isNotEmpty) {
            Future<void>.delayed(const Duration(milliseconds: 10), () {
              adapter.emitScanResults(
                const <BleDiscoveredDevice>[
                  BleDiscoveredDevice(
                    id: 'robot-2',
                    name: 'RobotOSLite',
                    rssi: -52,
                  ),
                ],
              );
            });
          }
        },
      );

      final device = await BleTransport.scan(
        withServices: <String>{BleConnectionOptions.defaultServiceUuid},
        timeout: const Duration(milliseconds: 120),
        platform: adapter,
      ).first;

      expect(device.id, 'robot-2');
      expect(
        adapter.scanRequests,
        <List<String>>[
          <String>[BleConnectionOptions.defaultServiceUuid],
        ],
      );
    });

    test('connect stops scan before starting gatt connection', () async {
      final adapter = _FakeBlePlatformAdapter(
        session: _FakeBleConnectionSession(),
      );
      final session = adapter.session;
      final transport = BleTransport(
        const BleConnectionOptions(deviceId: 'robot-3', mtuRequest: 23),
        platform: adapter,
      );

      session.onConnect = () {
        expect(adapter.stopScanCalls, 1);
      };

      await transport.connect();
    });

    test('send splits payload according to mtu', () async {
      final session = _FakeBleConnectionSession();
      final transport = BleTransport(
        const BleConnectionOptions(deviceId: 'robot-1', mtuRequest: 23),
        platform: _FakeBlePlatformAdapter(session: session),
      );

      await transport.connect();
      await transport
          .send(Uint8List.fromList(List<int>.generate(55, (i) => i)));

      expect(session.notifyEnabled, isTrue);
      expect(session.writes.map((item) => item.value.length).toList(),
          <int>[20, 20, 15]);
      expect(session.writes.every((item) => item.withoutResponse), isTrue);
    });

    test('incoming notify chunks are decoded into frames', () async {
      final session = _FakeBleConnectionSession();
      final transport = BleTransport(
        const BleConnectionOptions(deviceId: 'robot-1', mtuRequest: 23),
        platform: _FakeBlePlatformAdapter(session: session),
      );
      final completer = Completer<RobotFrame>();
      final subscription = transport.frames.listen(completer.complete);

      await transport.connect();

      final encoded = encodeFrame(
        RobotFrame(
          type: FrameType.state,
          seq: 9,
          payload: Uint8List.fromList(<int>[90, 1, 2, 3, 4, 5, 6]),
        ),
      );
      session.emitNotifyChunk(encoded.sublist(0, 6));
      session.emitNotifyChunk(encoded.sublist(6));

      final frame = await completer.future;
      expect(frame.type, FrameType.state);
      expect(frame.seq, 9);
      expect(frame.payload, orderedEquals(<int>[90, 1, 2, 3, 4, 5, 6]));

      await subscription.cancel();
    });
  });
}

class _FakeBlePlatformAdapter implements BlePlatformAdapter {
  _FakeBlePlatformAdapter({
    required this.session,
    this.onStartScan,
  });

  final _scanController =
      StreamController<List<BleDiscoveredDevice>>.broadcast();
  final _FakeBleConnectionSession session;
  final FutureOr<void> Function(List<String> serviceUuids, Duration timeout)?
      onStartScan;
  final List<List<String>> scanRequests = <List<String>>[];
  int stopScanCalls = 0;

  void emitScanResults(List<BleDiscoveredDevice> devices) {
    _scanController.add(devices);
  }

  @override
  Stream<List<BleDiscoveredDevice>> get scanResults => _scanController.stream;

  @override
  BleConnectionSession createSession(String deviceId) => session;

  @override
  Future<void> startScan({
    required List<String> serviceUuids,
    required Duration timeout,
  }) async {
    scanRequests.add(List<String>.from(serviceUuids));
    await onStartScan?.call(serviceUuids, timeout);
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls += 1;
  }

  @override
  Future<void> waitUntilReady() async {}
}

class _WriteCall {
  const _WriteCall({required this.value, required this.withoutResponse});

  final List<int> value;
  final bool withoutResponse;
}

class _FakeBleConnectionSession implements BleConnectionSession {
  final _connectionController = StreamController<bool>.broadcast();
  final _notifyController = StreamController<List<int>>.broadcast();
  final List<_WriteCall> writes = <_WriteCall>[];
  bool notifyEnabled = false;
  void Function()? onConnect;
  int _mtuNow = 23;
  bool _isConnected = false;

  void emitNotifyChunk(List<int> value) {
    _notifyController.add(value);
  }

  @override
  Stream<bool> get connectionState => _connectionController.stream;

  @override
  int get mtuNow => _mtuNow;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect({
    required Duration timeout,
    required BlePluginLicense pluginLicense,
  }) async {
    onConnect?.call();
    _isConnected = true;
    _connectionController.add(true);
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectionController.add(false);
  }

  @override
  Future<void> discoverServices() async {}

  @override
  Stream<List<int>> onCharacteristicValue({
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    return _notifyController.stream;
  }

  @override
  Future<int?> requestMtu(int mtu) async {
    _mtuNow = mtu;
    return mtu;
  }

  @override
  Future<void> setNotifyValue({
    required String serviceUuid,
    required String characteristicUuid,
    required bool enabled,
  }) async {
    notifyEnabled = enabled;
  }

  @override
  Future<void> write({
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    required bool withoutResponse,
  }) async {
    writes.add(_WriteCall(value: value, withoutResponse: withoutResponse));
  }
}
