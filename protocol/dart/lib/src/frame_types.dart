enum FrameType {
  cmd(0x01),
  state(0x02),
  ack(0x03);

  const FrameType(this.value);

  final int value;

  static FrameType fromValue(int value) {
    return FrameType.values.firstWhere(
      (item) => item.value == value,
      orElse: () => throw ProtocolException(
        'Unsupported frame type: 0x${value.toRadixString(16)}',
      ),
    );
  }
}

enum CommandId {
  move(0x01),
  stand(0x10),
  sit(0x11),
  stop(0x12);

  const CommandId(this.value);

  final int value;

  static CommandId fromValue(int value) {
    return CommandId.values.firstWhere(
      (item) => item.value == value,
      orElse: () => throw ProtocolException(
        'Unsupported command id: 0x${value.toRadixString(16)}',
      ),
    );
  }
}

class ProtocolException implements Exception {
  const ProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}
