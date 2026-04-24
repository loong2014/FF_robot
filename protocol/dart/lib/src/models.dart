import 'dart:typed_data';

import 'frame_types.dart';

class RobotFrame {
  const RobotFrame({
    required this.type,
    required this.seq,
    required this.payload,
  });

  final FrameType type;
  final int seq;
  final Uint8List payload;
}

abstract class RobotCommand {
  const RobotCommand();

  CommandId get commandId;

  bool get isMove;
}

class MoveCommand extends RobotCommand {
  const MoveCommand({required this.vx, required this.vy, required this.yaw});

  final double vx;
  final double vy;
  final double yaw;

  @override
  CommandId get commandId => CommandId.move;

  @override
  bool get isMove => true;
}

class DiscreteCommand extends RobotCommand {
  const DiscreteCommand(this.commandId);

  @override
  final CommandId commandId;

  @override
  bool get isMove => false;
}

class SkillInvokeCommand extends RobotCommand {
  SkillInvokeCommand({
    required this.serviceId,
    required this.operation,
    required List<int> args,
    this.requireAck = true,
  }) : args = Uint8List.fromList(args) {
    if (this.args.length > 0xFF) {
      throw const ProtocolException(
        'Skill invoke args must fit in uint8 length field',
      );
    }
  }

  factory SkillInvokeCommand.doAction({
    required int actionId,
    bool requireAck = true,
  }) {
    if (actionId < 0 || actionId > 0xFFFF) {
      throw const ProtocolException('Action id must fit in uint16');
    }
    final bytes = ByteData(2)..setUint16(0, actionId, Endian.little);
    return SkillInvokeCommand(
      serviceId: ServiceId.doAction,
      operation: Operation.execute,
      args: bytes.buffer.asUint8List(),
      requireAck: requireAck,
    );
  }

  factory SkillInvokeCommand.doDogBehavior({
    required DogBehavior behavior,
    bool requireAck = true,
  }) {
    return SkillInvokeCommand(
      serviceId: ServiceId.doDogBehavior,
      operation: Operation.execute,
      args: <int>[behavior.value],
      requireAck: requireAck,
    );
  }

  final ServiceId serviceId;
  final Operation operation;
  final Uint8List args;
  final bool requireAck;

  @override
  CommandId get commandId => CommandId.skillInvoke;

  int get actionId {
    if (serviceId != ServiceId.doAction || operation != Operation.execute) {
      throw StateError(
        'actionId is only available for doAction execute commands',
      );
    }
    if (args.length != 2) {
      throw StateError('doAction execute args must be 2 bytes');
    }
    return ByteData.sublistView(args).getUint16(0, Endian.little);
  }

  DogBehavior get behaviorId {
    if (serviceId != ServiceId.doDogBehavior ||
        operation != Operation.execute) {
      throw StateError(
        'behaviorId is only available for doDogBehavior execute commands',
      );
    }
    if (args.length != 1) {
      throw StateError('doDogBehavior execute args must be 1 byte');
    }
    return DogBehavior.fromValue(args.first);
  }

  @override
  bool get isMove => false;
}

class RobotState {
  const RobotState({
    required this.battery,
    required this.roll,
    required this.pitch,
    required this.yaw,
  });

  final int battery;
  final double roll;
  final double pitch;
  final double yaw;
}
