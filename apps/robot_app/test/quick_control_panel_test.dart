import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/quick_control_panel.dart';

class _FakeRobotClient extends RobotClient {
  _FakeRobotClient() : super();

  final List<String> calls = <String>[];

  @override
  Future<void> stand() async {
    calls.add('stand');
  }

  @override
  Future<void> sit() async {
    calls.add('sit');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> doDogBehavior(
    DogBehavior behavior, {
    bool requireAck = true,
  }) async {
    calls.add('behavior:${behavior.name}');
  }
}

void main() {
  testWidgets('QuickControlPanel renders common actions', (tester) async {
    final client = _FakeRobotClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickControlPanel(
            client: client,
            isConnected: true,
          ),
        ),
      ),
    );

    expect(find.text('基础姿态'), findsOneWidget);
    expect(find.text('常用行为'), findsOneWidget);
    expect(find.text('站立'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('招手'), findsOneWidget);
    expect(find.text('跳舞'), findsOneWidget);
  });

  testWidgets('QuickControlPanel invokes RobotClient when connected', (
    tester,
  ) async {
    final client = _FakeRobotClient();
    final messages = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickControlPanel(
            client: client,
            isConnected: true,
            onMessage: messages.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('站立'));
    await tester.pump();
    await tester.tap(find.text('招手'));
    await tester.pump();

    expect(client.calls, <String>['stand', 'behavior:waveHand']);
    expect(messages, containsAll(<String>['已发送 stand', '已发送 wave_hand']));
  });

  testWidgets('QuickControlPanel requires connection before sending', (
    tester,
  ) async {
    final client = _FakeRobotClient();
    var requireConnectionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickControlPanel(
            client: client,
            isConnected: false,
            onRequireConnection: () {
              requireConnectionCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('站立'));
    await tester.pump();

    expect(client.calls, isEmpty);
    expect(requireConnectionCount, 1);
  });
}
