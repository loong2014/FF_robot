import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/robot_skill_catalog.dart';
import 'package:robot_app/src/skill_control_page.dart';

class _FakeSkillRobotClient extends RobotClient {
  _FakeSkillRobotClient();

  final RobotConnectionState _connection = RobotConnectionState(
    transport: TransportKind.ble,
    status: ConnectionStatus.connected,
    updatedAt: DateTime(2026),
  );

  int? lastActionId;
  DogBehavior? lastBehavior;

  @override
  RobotConnectionState get currentConnection => _connection;

  @override
  Stream<RobotConnectionState> get connectionState =>
      Stream<RobotConnectionState>.value(_connection);

  @override
  Stream<RobotState> get stateStream => Stream<RobotState>.value(
        const RobotState(
          battery: 88,
          roll: 1.25,
          pitch: -0.5,
          yaw: 3.0,
        ),
      );

  @override
  Stream<RobotFrame> get frameStream => const Stream<RobotFrame>.empty();

  @override
  Stream<Object> get errors => const Stream<Object>.empty();

  @override
  Future<void> doAction(
    int actionId, {
    bool requireAck = true,
  }) async {
    lastActionId = actionId;
  }

  @override
  Future<void> doDogBehavior(
    DogBehavior behavior, {
    bool requireAck = true,
  }) async {
    lastBehavior = behavior;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 30,
  }) async {
    for (var index = 0; index < maxPumps; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    fail('Timed out waiting for $finder');
  }

  Future<void> pumpPage(WidgetTester tester, _FakeSkillRobotClient client,
      {int initialTabIndex = 0}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SkillControlPage(
          client: client,
          initialTabIndex: initialTabIndex,
          catalogFuture: Future<RobotSkillCatalog>.value(
            const RobotSkillCatalog(
              actions: <SkillActionItem>[
                SkillActionItem(actionId: 20593, actionName: 'draw_heart'),
                SkillActionItem(actionId: 20609, actionName: 'turn_left_90'),
              ],
              behaviors: <SkillBehaviorItem>[
                SkillBehaviorItem(
                  behaviorName: 'wave_hand',
                  behavior: DogBehavior.waveHand,
                ),
              ],
              duplicateActionIds: <int>{},
            ),
          ),
        ),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));
  }

  testWidgets('SkillControlPage shows status and sends do_action', (
    WidgetTester tester,
  ) async {
    final client = _FakeSkillRobotClient();

    await pumpPage(tester, client);
    await tester.pump();

    expect(find.text('完整动作控制'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('动作 2'), findsOneWidget);
    expect(find.text('行为 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '20593');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('action-20593:draw_heart')),
        matching: find.text('执行'),
      ),
    );
    await tester.pump();

    expect(client.lastActionId, 20593);
  });

  testWidgets('SkillControlPage sends supported dog behavior', (
    WidgetTester tester,
  ) async {
    final client = _FakeSkillRobotClient();

    await pumpPage(tester, client, initialTabIndex: 1);
    await tester.enterText(find.byType(TextField), 'wave_hand');
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('behavior-wave_hand')),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('behavior-wave_hand')),
        matching: find.text('执行'),
      ),
    );
    await tester.pump();

    expect(client.lastBehavior, DogBehavior.waveHand);
  });
}
