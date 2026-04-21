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
