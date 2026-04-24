import 'dart:typed_data';

import 'crc16.dart';
import 'frame_types.dart';
import 'models.dart';

const List<int> kMagic = <int>[0xAA, 0x55];
const int kMaxPayloadLength = 512;
const int kFrameOverhead = 8;
const int kMoveScale = 100;
const int kAngleScale = 100;

Uint8List encodeFrame(RobotFrame frame) {
  if (frame.seq < 0 || frame.seq > 0xFF) {
    throw ProtocolException('Sequence out of range: ${frame.seq}');
  }
  if (frame.payload.length > kMaxPayloadLength) {
    throw ProtocolException('Payload too large: ${frame.payload.length}');
  }

  final header = ByteData(4)
    ..setUint8(0, frame.type.value)
    ..setUint8(1, frame.seq)
    ..setUint16(2, frame.payload.length, Endian.little);

  final bodyBuilder = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(frame.payload);
  final body = bodyBuilder.toBytes();
  final crc = ByteData(2)..setUint16(0, crc16Ccitt(body), Endian.little);

  final builder = BytesBuilder(copy: false)
    ..add(kMagic)
    ..add(body)
    ..add(crc.buffer.asUint8List());
  return builder.toBytes();
}

RobotFrame decodeFrame(Uint8List data) {
  if (data.length < kFrameOverhead) {
    throw const ProtocolException('Frame too short');
  }
  if (data[0] != kMagic[0] || data[1] != kMagic[1]) {
    throw const ProtocolException('Invalid magic header');
  }

  final header = ByteData.sublistView(data, 2, 6);
  final typeValue = header.getUint8(0);
  final seq = header.getUint8(1);
  final payloadLength = header.getUint16(2, Endian.little);
  final expectedLength = kFrameOverhead + payloadLength;
  if (data.length != expectedLength) {
    throw const ProtocolException('Frame length mismatch');
  }

  final payload = Uint8List.sublistView(data, 6, 6 + payloadLength);
  final expectedCrc = ByteData.sublistView(
    data,
    data.length - 2,
  ).getUint16(0, Endian.little);
  final actualCrc = crc16Ccitt(data.sublist(2, data.length - 2));
  if (expectedCrc != actualCrc) {
    throw ProtocolException(
      'CRC mismatch: expected=0x${expectedCrc.toRadixString(16)} actual=0x${actualCrc.toRadixString(16)}',
    );
  }

  return RobotFrame(
    type: FrameType.fromValue(typeValue),
    seq: seq,
    payload: Uint8List.fromList(payload),
  );
}

RobotFrame buildCommandFrame(RobotCommand command, int seq) {
  return RobotFrame(
    type: FrameType.cmd,
    seq: seq & 0xFF,
    payload: encodeCommandPayload(command),
  );
}

RobotFrame buildStateFrame(RobotState state, int seq) {
  final payload = ByteData(7)
    ..setUint8(0, state.battery.clamp(0, 100).toInt())
    ..setInt16(1, _scaleToI16(state.roll, kAngleScale), Endian.little)
    ..setInt16(3, _scaleToI16(state.pitch, kAngleScale), Endian.little)
    ..setInt16(5, _scaleToI16(state.yaw, kAngleScale), Endian.little);
  return RobotFrame(
    type: FrameType.state,
    seq: seq & 0xFF,
    payload: payload.buffer.asUint8List(),
  );
}

RobotFrame buildAckFrame(int seq) {
  final ackSeq = seq & 0xFF;
  return RobotFrame(
    type: FrameType.ack,
    seq: ackSeq,
    payload: Uint8List.fromList(<int>[ackSeq]),
  );
}

Uint8List encodeCommandPayload(RobotCommand command) {
  if (command is MoveCommand) {
    final payload = ByteData(7)
      ..setUint8(0, command.commandId.value)
      ..setInt16(1, _scaleToI16(command.vx, kMoveScale), Endian.little)
      ..setInt16(3, _scaleToI16(command.vy, kMoveScale), Endian.little)
      ..setInt16(5, _scaleToI16(command.yaw, kAngleScale), Endian.little);
    return payload.buffer.asUint8List();
  }

  return Uint8List.fromList(<int>[command.commandId.value]);
}

RobotCommand parseCommandPayload(List<int> payload) {
  if (payload.isEmpty) {
    throw const ProtocolException('Empty command payload');
  }

  final commandId = CommandId.fromValue(payload.first);
  if (commandId == CommandId.move) {
    if (payload.length != 7) {
      throw const ProtocolException('Move payload must be 7 bytes');
    }
    final data = ByteData.sublistView(Uint8List.fromList(payload), 1);
    return MoveCommand(
      vx: data.getInt16(0, Endian.little) / kMoveScale,
      vy: data.getInt16(2, Endian.little) / kMoveScale,
      yaw: data.getInt16(4, Endian.little) / kAngleScale,
    );
  }

  if (payload.length != 1) {
    throw const ProtocolException('Discrete payload must be 1 byte');
  }
  return DiscreteCommand(commandId);
}

RobotState parseStatePayload(List<int> payload) {
  if (payload.length != 7) {
    throw const ProtocolException('State payload must be 7 bytes');
  }
  final data = ByteData.sublistView(Uint8List.fromList(payload));
  return RobotState(
    battery: data.getUint8(0),
    roll: data.getInt16(1, Endian.little) / kAngleScale,
    pitch: data.getInt16(3, Endian.little) / kAngleScale,
    yaw: data.getInt16(5, Endian.little) / kAngleScale,
  );
}

int parseAckPayload(List<int> payload) {
  if (payload.length != 1) {
    throw const ProtocolException('Ack payload must be 1 byte');
  }
  return payload.first;
}

int _scaleToI16(double value, int scale) {
  final scaled = (value * scale).round();
  if (scaled < -32768 || scaled > 32767) {
    throw ProtocolException('Scaled value out of int16 range: $value');
  }
  return scaled;
}
