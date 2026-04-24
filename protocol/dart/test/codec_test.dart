import 'package:robot_protocol/robot_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('move command round trip', () {
    final frame = buildCommandFrame(
      const MoveCommand(vx: 0.5, vy: -0.1, yaw: 1.2),
      7,
    );

    final decoded = decodeFrame(encodeFrame(frame));
    final parsed = parseCommandPayload(decoded.payload);

    expect(parsed, isA<MoveCommand>());
    expect((parsed as MoveCommand).vx, closeTo(0.5, 0.01));
    expect(parsed.vy, closeTo(-0.1, 0.01));
    expect(parsed.yaw, closeTo(1.2, 0.01));
  });

  test('skill doAction round trip', () {
    final frame = buildCommandFrame(
      SkillInvokeCommand.doAction(actionId: 20524),
      8,
    );

    final decoded = decodeFrame(encodeFrame(frame));
    final parsed = parseCommandPayload(decoded.payload);

    expect(parsed, isA<SkillInvokeCommand>());
    expect((parsed as SkillInvokeCommand).actionId, 20524);
    expect(parsed.requireAck, isTrue);
  });

  test('skill doDogBehavior round trip', () {
    final frame = buildCommandFrame(
      SkillInvokeCommand.doDogBehavior(
        behavior: DogBehavior.waveHand,
        requireAck: false,
      ),
      9,
    );

    final decoded = decodeFrame(encodeFrame(frame));
    final parsed = parseCommandPayload(decoded.payload);

    expect(parsed, isA<SkillInvokeCommand>());
    expect((parsed as SkillInvokeCommand).behaviorId, DogBehavior.waveHand);
    expect(parsed.requireAck, isFalse);
  });
}
