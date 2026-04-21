import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/action_engine.dart';
import 'package:robot_app/src/action_models.dart';
import 'package:robot_app/src/action_program_view.dart';

class _FakeRobotClient extends RobotClient {
  _FakeRobotClient() : super();

  @override
  Future<void> stand() async {}

  @override
  Future<void> sit() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> move(double vx, double vy, double yaw) async {}
}

void main() {
  testWidgets('ActionProgramView renders initial program and controls', (
    tester,
  ) async {
    final client = _FakeRobotClient();
    final engine = ActionEngine(client);
    final program = <ActionStep>[
      ActionStep.stand(),
      ActionStep.sit(),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActionProgramView(
              engine: engine,
              initialProgram: program,
            ),
          ),
        ),
      ),
    );

    expect(find.text('动作编排'), findsOneWidget);
    expect(find.text('站立 · stand'), findsOneWidget);
    expect(find.text('坐下 · sit'), findsOneWidget);
    expect(find.text('执行'), findsOneWidget);
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);

    await engine.dispose();
  });

  testWidgets('ActionProgramView shows empty placeholder when cleared', (
    tester,
  ) async {
    final client = _FakeRobotClient();
    final engine = ActionEngine(client);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActionProgramView(engine: engine),
          ),
        ),
      ),
    );

    expect(find.text('还没有动作，使用上面的按钮新增。'), findsOneWidget);

    await engine.dispose();
  });
}
