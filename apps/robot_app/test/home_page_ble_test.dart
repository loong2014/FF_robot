import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/ble_device_store.dart';
import 'package:robot_app/src/home_page.dart';

class _MemoryBleDeviceStore implements BleDeviceStore {
  _MemoryBleDeviceStore({this.savedDevice});

  SavedBleDevice? savedDevice;
  int loadCalls = 0;
  int saveCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    savedDevice = null;
  }

  @override
  Future<SavedBleDevice?> load() async {
    loadCalls += 1;
    return savedDevice;
  }

  @override
  Future<void> save(SavedBleDevice device) async {
    saveCalls += 1;
    savedDevice = device;
  }
}

class _FakeHomeRobotClient extends RobotClient {
  _FakeHomeRobotClient();

  final StreamController<RobotConnectionState> _connectionController =
      StreamController<RobotConnectionState>.broadcast();
  RobotConnectionState _currentState = RobotConnectionState.idle();
  BleConnectionOptions? lastBleOptions;

  @override
  Stream<RobotConnectionState> get connectionState =>
      Stream<RobotConnectionState>.multi(
        (controller) {
          controller.add(_currentState);
          final subscription = _connectionController.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
          controller.onCancel = subscription.cancel;
        },
        isBroadcast: true,
      );

  @override
  Stream<RobotState> get stateStream => const Stream<RobotState>.empty();

  @override
  Stream<RobotFrame> get frameStream => const Stream<RobotFrame>.empty();

  @override
  Stream<Object> get errors => const Stream<Object>.empty();

  @override
  Future<void> connectBLE({
    BleConnectionOptions options = const BleConnectionOptions(),
  }) async {
    lastBleOptions = options;
    _emitConnection(
      transport: TransportKind.ble,
      status: ConnectionStatus.connecting,
    );
    _emitConnection(
      transport: TransportKind.ble,
      status: ConnectionStatus.connected,
    );
  }

  @override
  Future<void> disconnect() async {
    _emitConnection(
      transport: TransportKind.none,
      status: ConnectionStatus.idle,
    );
  }

  void _emitConnection({
    required TransportKind transport,
    required ConnectionStatus status,
  }) {
    _currentState = RobotConnectionState(
      transport: transport,
      status: status,
      updatedAt: DateTime.now(),
    );
    _connectionController.add(_currentState);
  }

  @override
  Future<void> dispose() async {
    await _connectionController.close();
  }
}

void main() {
  Future<void> pumpHomePage(
    WidgetTester tester, {
    required _FakeHomeRobotClient client,
    required _MemoryBleDeviceStore store,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          client: client,
          bleDeviceStore: store,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('HomePage auto reconnects last saved BLE device on launch', (
    WidgetTester tester,
  ) async {
    final client = _FakeHomeRobotClient();
    final store = _MemoryBleDeviceStore(
      savedDevice: const SavedBleDevice(id: 'robot-1', name: 'RobotDog-1'),
    );

    await pumpHomePage(tester, client: client, store: store);

    expect(store.loadCalls, 1);
    expect(client.lastBleOptions?.deviceId, 'robot-1');
    expect(find.textContaining('RobotDog-1'), findsWidgets);
  });

  testWidgets('HomePage clears saved BLE device after manual disconnect', (
    WidgetTester tester,
  ) async {
    final client = _FakeHomeRobotClient();
    final store = _MemoryBleDeviceStore(
      savedDevice: const SavedBleDevice(id: 'robot-1', name: 'RobotDog-1'),
    );

    await pumpHomePage(tester, client: client, store: store);
    await tester.tap(find.text('断开'));
    await tester.pump();

    expect(store.clearCalls, 1);
    expect(store.savedDevice, isNull);
  });
}
