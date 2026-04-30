import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/control_page.dart';
import 'package:robot_app/src/joystick_pad.dart';

class _FakeRobotClient extends RobotClient {
  _FakeRobotClient() : super();

  final StreamController<RobotConnectionState> _connectionController =
      StreamController<RobotConnectionState>.broadcast();
  final StreamController<RobotState> _stateController =
      StreamController<RobotState>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();
  final List<String> calls = <String>[];

  @override
  Stream<RobotConnectionState> get connectionState =>
      Stream<RobotConnectionState>.multi(
        (controller) {
          controller.add(
            RobotConnectionState(
              transport: TransportKind.ble,
              status: ConnectionStatus.connected,
              updatedAt: DateTime.now(),
            ),
          );
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
  Stream<RobotState> get stateStream => Stream<RobotState>.multi(
        (controller) {
          controller.add(
            const RobotState(battery: 66, roll: 0, pitch: 0, yaw: 0),
          );
          final subscription = _stateController.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
          controller.onCancel = subscription.cancel;
        },
        isBroadcast: true,
      );

  @override
  Stream<Object> get errors => _errorController.stream;

  void emitConnection(RobotConnectionState state) {
    _connectionController.add(state);
  }

  void emitError(Object error) {
    _errorController.add(error);
  }

  @override
  Future<void> move(double vx, double vy, double yaw) async {
    calls.add(
      'move(${vx.toStringAsFixed(2)},${vy.toStringAsFixed(2)},${yaw.toStringAsFixed(2)})',
    );
  }

  @override
  Future<void> moveLatest(double vx, double vy, double yaw) async {
    calls.add(
      'moveLatest(${vx.toStringAsFixed(2)},${vy.toStringAsFixed(2)},${yaw.toStringAsFixed(2)})',
    );
  }

  @override
  Future<void> stand() async {
    calls.add('stand');
  }

  @override
  Future<void> standLatest() async {
    calls.add('standLatest');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> stopLatest() async {
    calls.add('stopLatest');
  }

  @override
  Future<void> emergencyStop() async {
    calls.add('emergencyStop');
  }

  @override
  Future<void> emergencyStopLatest() async {
    calls.add('emergencyStopLatest');
  }

  @override
  Future<void> enterMotionMode() async {
    calls.add('enterMotionMode');
  }

  @override
  Future<void> enterMotionModeLatest() async {
    calls.add('enterMotionModeLatest');
  }

  @override
  Future<void> recover() async {
    calls.add('recover');
  }

  @override
  Future<void> recoverLatest() async {
    calls.add('recoverLatest');
  }

  @override
  Future<void> doAction(int actionId, {bool requireAck = true}) async {
    calls.add('action:$actionId');
  }

  @override
  Future<void> doActionLatest(int actionId, {bool requireAck = true}) async {
    calls.add('actionLatest:$actionId');
  }

  @override
  Future<void> doDogBehavior(
    DogBehavior behavior, {
    bool requireAck = true,
  }) async {
    calls.add('behavior:${behavior.name}');
  }

  @override
  Future<void> doDogBehaviorLatest(
    DogBehavior behavior, {
    bool requireAck = true,
  }) async {
    calls.add('behaviorLatest:${behavior.name}');
  }
}

void main() {
  Future<void> pumpControlPage(
    WidgetTester tester,
    _FakeRobotClient client,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ControlPage(client: client),
      ),
    );
    await tester.pump();
  }

  testWidgets('ControlPage renders dual joysticks and action grid', (
    WidgetTester tester,
  ) async {
    final client = _FakeRobotClient();

    await pumpControlPage(tester, client);

    expect(find.text('移动'), findsOneWidget);
    expect(find.text('转向'), findsOneWidget);
    expect(find.text('站立'), findsOneWidget);
    expect(find.text('右空翻'), findsOneWidget);
    expect(find.text('66%'), findsOneWidget);
    expect(find.text('急停'), findsOneWidget);
  });

  testWidgets('ControlPage action buttons invoke RobotClient mappings', (
    WidgetTester tester,
  ) async {
    final client = _FakeRobotClient();

    await pumpControlPage(tester, client);

    await tester.tap(find.text('站立'));
    await tester.pump();
    await tester.tap(find.text('比心'));
    await tester.pump();
    await tester.tap(find.text('急停'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('急停'));
    await tester.pump();

    expect(client.calls, contains('stand'));
    expect(client.calls, contains('action:20593'));
    expect(client.calls, contains('emergencyStop'));
  });

  testWidgets(
    'ControlPage emergency button toggles restore and blocks joystick while stopped',
    (WidgetTester tester) async {
      final client = _FakeRobotClient();

      await pumpControlPage(tester, client);

      await tester.tap(find.text('急停'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('急停'));
      await tester.pump();

      expect(find.text('恢复'), findsOneWidget);
      expect(client.calls.last, 'emergencyStop');

      final joystickFinder = find.byType(JoystickPad).first;
      final gesture = await tester.startGesture(
        tester.getCenter(joystickFinder),
      );
      await gesture.moveBy(const Offset(30, -36));
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.up();
      await tester.pump();

      expect(client.calls.contains('enterMotionMode'), isFalse);
      expect(
        client.calls.any((String call) => call.startsWith('move(')),
        isFalse,
      );

      await tester.tap(find.text('恢复'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('恢复'));
      await tester.pump();

      expect(find.text('急停'), findsOneWidget);
      expect(client.calls.last, 'recover');

      final resumeGesture = await tester.startGesture(
        tester.getCenter(joystickFinder),
      );
      await resumeGesture.moveBy(const Offset(30, -36));
      await tester.pump(const Duration(milliseconds: 120));
      await resumeGesture.up();
      await tester.pump();

      expect(
        client.calls.where((String call) => call == 'enterMotionMode').length,
        1,
      );
      expect(
        client.calls.any((String call) => call.startsWith('move(')),
        isTrue,
      );
    },
  );

  testWidgets(
    'ControlPage emergency button single tap shows hint after 1s without command',
    (WidgetTester tester) async {
      final client = _FakeRobotClient();

      await pumpControlPage(tester, client);

      await tester.tap(find.text('急停'));
      await tester.pump();

      expect(client.calls, isNot(contains('emergencyStop')));
      expect(find.text('请双击按钮'), findsNothing);

      await tester.pump(const Duration(seconds: 1));

      expect(client.calls, isNot(contains('emergencyStop')));
      expect(find.text('请双击按钮'), findsOneWidget);
    },
  );

  testWidgets('ControlPage joystick drag sends move and release resets to zero',
      (
    WidgetTester tester,
  ) async {
    final client = _FakeRobotClient();

    await pumpControlPage(tester, client);

    final joystickFinder = find.byType(JoystickPad).first;
    final gesture = await tester.startGesture(
      tester.getCenter(joystickFinder),
    );
    await gesture.moveBy(const Offset(30, -36));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump();

    expect(client.calls.first, 'enterMotionMode');
    expect(
      client.calls.any((String call) => call.startsWith('move(')),
      isTrue,
    );
    expect(client.calls.last, 'move(0.00,0.00,0.00)');

    client.calls.clear();
    final nextGesture = await tester.startGesture(
      tester.getCenter(joystickFinder),
    );
    await nextGesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 120));
    await nextGesture.up();
    await tester.pump();

    expect(client.calls.first, 'enterMotionMode');
  });

  testWidgets(
    'ControlPage stops joystick loop and resets motion mode on BLE disconnect',
    (WidgetTester tester) async {
      final client = _FakeRobotClient();

      await pumpControlPage(tester, client);

      final joystickFinder = find.byType(JoystickPad).first;
      final gesture = await tester.startGesture(
        tester.getCenter(joystickFinder),
      );
      await gesture.moveBy(const Offset(30, -36));
      await tester.pump(const Duration(milliseconds: 120));
      final callsBeforeDisconnect = client.calls.length;

      client.emitConnection(
        RobotConnectionState(
          transport: TransportKind.ble,
          status: ConnectionStatus.reconnecting,
          updatedAt: DateTime.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 260));

      expect(client.calls.length, callsBeforeDisconnect);
      expect(find.textContaining('BLE 已断开'), findsOneWidget);

      client.emitConnection(
        RobotConnectionState(
          transport: TransportKind.ble,
          status: ConnectionStatus.connected,
          updatedAt: DateTime.now(),
        ),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      client.calls.clear();
      final resumedGesture = await tester.startGesture(
        tester.getCenter(joystickFinder),
      );
      await resumedGesture.moveBy(const Offset(30, -36));
      await tester.pump(const Duration(milliseconds: 120));
      await resumedGesture.up();
      await tester.pump();

      expect(client.calls.first, 'enterMotionMode');
    },
  );

  testWidgets(
    'ControlPage resets motion mode after command error without disconnect',
    (WidgetTester tester) async {
      final client = _FakeRobotClient();

      await pumpControlPage(tester, client);

      final joystickFinder = find.byType(JoystickPad).first;
      final gesture = await tester.startGesture(
        tester.getCenter(joystickFinder),
      );
      await gesture.moveBy(const Offset(30, -36));
      await tester.pump(const Duration(milliseconds: 120));

      client.emitError(StateError('transient command failure'));
      await tester.pump();
      client.calls.clear();

      await gesture.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.up();
      await tester.pump();

      expect(client.calls.first, 'enterMotionMode');
    },
  );
}
