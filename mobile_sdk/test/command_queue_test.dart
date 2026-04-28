import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('move queue only keeps latest', () {
    final queue = CommandQueue();

    queue.enqueue(
      QueuedCommand(
        seq: 1,
        command: const MoveCommand(vx: 0.1, vy: 0.0, yaw: 0.0),
        frameBytes: encodeFrame(
          buildCommandFrame(const MoveCommand(vx: 0.1, vy: 0.0, yaw: 0.0), 1),
        ),
        isMove: true,
      ),
    );
    queue.enqueue(
      QueuedCommand(
        seq: 2,
        command: const MoveCommand(vx: 0.2, vy: 0.0, yaw: 0.0),
        frameBytes: encodeFrame(
          buildCommandFrame(const MoveCommand(vx: 0.2, vy: 0.0, yaw: 0.0), 2),
        ),
        isMove: true,
      ),
    );

    expect(queue.promoteNext(DateTime.now())?.seq, 2);
  });

  test('discrete queue preserves FIFO by default', () {
    final queue = CommandQueue();

    queue.enqueue(
      QueuedCommand(
        seq: 1,
        command: const DiscreteCommand(CommandId.stand),
        frameBytes: encodeFrame(
          buildCommandFrame(const DiscreteCommand(CommandId.stand), 1),
        ),
        isMove: false,
      ),
    );
    queue.enqueue(
      QueuedCommand(
        seq: 2,
        command: const DiscreteCommand(CommandId.sit),
        frameBytes: encodeFrame(
          buildCommandFrame(const DiscreteCommand(CommandId.sit), 2),
        ),
        isMove: false,
      ),
    );

    expect(queue.promoteNext(DateTime.now())?.seq, 1);
    expect(queue.acknowledge(1), isTrue);
    expect(queue.promoteNext(DateTime.now())?.seq, 2);
  });

  test('discrete command drops unsent move command', () {
    final queue = CommandQueue();

    queue.enqueue(
      QueuedCommand(
        seq: 1,
        command: const MoveCommand(vx: 0.1, vy: 0.0, yaw: 0.0),
        frameBytes: encodeFrame(
          buildCommandFrame(const MoveCommand(vx: 0.1, vy: 0.0, yaw: 0.0), 1),
        ),
        isMove: true,
      ),
    );
    queue.enqueue(
      QueuedCommand(
        seq: 2,
        command: const DiscreteCommand(CommandId.stop),
        frameBytes: encodeFrame(
          buildCommandFrame(const DiscreteCommand(CommandId.stop), 2),
        ),
        isMove: false,
      ),
    );

    expect(queue.promoteNext(DateTime.now())?.seq, 2);
    expect(queue.acknowledge(2), isTrue);
    expect(queue.promoteNext(DateTime.now()), isNull);
  });

  test('enqueueLatest drops unsent discrete commands and keeps last command',
      () {
    final queue = CommandQueue();

    queue.enqueue(
      QueuedCommand(
        seq: 1,
        command: const DiscreteCommand(CommandId.stand),
        frameBytes: encodeFrame(
          buildCommandFrame(const DiscreteCommand(CommandId.stand), 1),
        ),
        isMove: false,
      ),
    );
    queue.enqueueLatest(
      QueuedCommand(
        seq: 2,
        command: const DiscreteCommand(CommandId.sit),
        frameBytes: encodeFrame(
          buildCommandFrame(const DiscreteCommand(CommandId.sit), 2),
        ),
        isMove: false,
      ),
    );
    queue.enqueueLatest(
      QueuedCommand(
        seq: 3,
        command: SkillInvokeCommand.doAction(actionId: 20593),
        frameBytes: encodeFrame(
          buildCommandFrame(
            SkillInvokeCommand.doAction(actionId: 20593),
            3,
          ),
        ),
        isMove: false,
      ),
    );

    expect(queue.promoteNext(DateTime.now())?.seq, 3);
    expect(queue.acknowledge(3), isTrue);
    expect(queue.promoteNext(DateTime.now()), isNull);
  });

  test('enqueueLatest marks inflight command as superseded', () {
    final queue = CommandQueue();

    queue.enqueueLatest(
      QueuedCommand(
        seq: 1,
        command: const DiscreteCommand(CommandId.stand),
        frameBytes: encodeFrame(
          buildCommandFrame(const DiscreteCommand(CommandId.stand), 1),
        ),
        isMove: false,
      ),
    );
    expect(queue.promoteNext(DateTime.now())?.seq, 1);

    queue.enqueueLatest(
      QueuedCommand(
        seq: 2,
        command: const DiscreteCommand(CommandId.sit),
        frameBytes: encodeFrame(
          buildCommandFrame(const DiscreteCommand(CommandId.sit), 2),
        ),
        isMove: false,
      ),
    );

    expect(queue.inflight?.seq, 1);
    expect(queue.inflight?.superseded, isTrue);
  });
}
