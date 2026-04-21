import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_protocol/robot_protocol.dart';
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
}
