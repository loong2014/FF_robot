import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/action_engine.dart';
import 'package:robot_app/src/action_models.dart';

class _FakeRobotClient extends RobotClient {
  _FakeRobotClient() : super();

  final List<String> calls = <String>[];
  final Map<String, int> failUntil = <String, int>{};
  final Map<String, int> callCounts = <String, int>{};

  Completer<void>? blockStand;
  Completer<void>? blockMove;

  @override
  Future<void> stand() async {
    _record('stand');
    if (blockStand != null) {
      await blockStand!.future;
    }
  }

  @override
  Future<void> sit() async {
    _record('sit');
  }

  @override
  Future<void> stop() async {
    _record('stop');
  }

  @override
  Future<void> move(double vx, double vy, double yaw) async {
    _record('move($vx,$vy,$yaw)', key: 'move');
    if (blockMove != null) {
      await blockMove!.future;
    }
  }

  void _record(String call, {String? key}) {
    calls.add(call);
    final counterKey = key ?? call;
    final next = (callCounts[counterKey] ?? 0) + 1;
    callCounts[counterKey] = next;
    final failCount = failUntil[counterKey] ?? 0;
    if (next <= failCount) {
      throw StateError('transient failure on $call');
    }
  }
}

Future<void> _noSleep(Duration _) async {}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('ActionEngine', () {
    test('runs sequentially and marks each step done', () async {
      final client = _FakeRobotClient();
      final engine = ActionEngine(client, sleep: _noSleep);
      final progressLog = <ActionProgress>[];
      final sub = engine.progressStream.listen(progressLog.add);

      final program = <ActionStep>[
        ActionStep.stand(),
        ActionStep.sit(),
      ];

      await engine.run(program);
      await sub.cancel();

      expect(engine.status, ActionEngineStatus.completed);
      expect(client.calls, containsAllInOrder(<String>['stand', 'sit']));
      final finalSnapshot = engine.currentProgress;
      expect(finalSnapshot.engineStatus, ActionEngineStatus.completed);
      expect(
        finalSnapshot.steps.map((s) => s.status).toList(),
        <ActionStepStatus>[ActionStepStatus.done, ActionStepStatus.done],
      );

      await engine.dispose();
    });

    test('retries failing step and reports attempts', () async {
      final client = _FakeRobotClient()..failUntil['stand'] = 2;
      final engine = ActionEngine(client, sleep: _noSleep);

      final program = <ActionStep>[
        ActionStep.stand(maxRetries: 3),
      ];
      await engine.run(program);

      final progress = engine.currentProgress;
      expect(progress.engineStatus, ActionEngineStatus.completed);
      expect(progress.steps.single.status, ActionStepStatus.done);
      expect(progress.steps.single.attempts, 3);
      expect(client.callCounts['stand'], 3);

      await engine.dispose();
    });

    test(
      'stops program and marks remaining as skipped when step keeps failing',
      () async {
        final client = _FakeRobotClient()..failUntil['stand'] = 5;
        final engine = ActionEngine(client, sleep: _noSleep);

        final program = <ActionStep>[
          ActionStep.stand(maxRetries: 1),
          ActionStep.sit(),
        ];
        await engine.run(program);

        final progress = engine.currentProgress;
        expect(progress.engineStatus, ActionEngineStatus.stopped);
        expect(progress.steps[0].status, ActionStepStatus.failed);
        expect(progress.steps[0].attempts, 2);
        expect(progress.steps[0].errorMessage, contains('transient failure'));
        expect(progress.steps[1].status, ActionStepStatus.skipped);
        expect(client.callCounts['sit'] ?? 0, 0);

        await engine.dispose();
      },
    );

    test('pause suspends execution until resume', () async {
      final client = _FakeRobotClient()..blockStand = Completer<void>();
      final engine = ActionEngine(client, sleep: _noSleep);

      final program = <ActionStep>[
        ActionStep.stand(),
        ActionStep.sit(),
      ];
      final future = engine.run(program);
      await _flush();

      engine.pause();
      expect(engine.status, ActionEngineStatus.paused);
      expect(client.calls.contains('sit'), isFalse);

      client.blockStand!.complete();
      await _flush();

      expect(engine.status, ActionEngineStatus.paused);
      expect(client.calls.contains('sit'), isFalse);

      engine.resume();
      await future;

      expect(engine.status, ActionEngineStatus.completed);
      expect(client.calls, containsAllInOrder(<String>['stand', 'sit']));

      await engine.dispose();
    });

    test('stop halts execution and invokes client.stop', () async {
      final client = _FakeRobotClient()..blockStand = Completer<void>();
      final engine = ActionEngine(client, sleep: _noSleep);

      final program = <ActionStep>[
        ActionStep.stand(),
        ActionStep.sit(),
      ];
      final future = engine.run(program);
      await _flush();

      await engine.stop();
      client.blockStand!.complete();
      await future;

      expect(engine.status, ActionEngineStatus.stopped);
      final progress = engine.currentProgress;
      expect(
        progress.steps.any((s) => s.status == ActionStepStatus.skipped),
        isTrue,
      );
      expect(client.calls.contains('stop'), isTrue);
      expect(client.calls.contains('sit'), isFalse);

      await engine.dispose();
    });
  });
}
