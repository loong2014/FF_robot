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
  stop(0x12),
  skillInvoke(0x20);

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

enum ServiceId {
  doAction(0x01),
  doDogBehavior(0x02),
  setFan(0x03),
  onPatrol(0x04),
  phoneCall(0x05),
  watchDog(0x06),
  setMotionParams(0x07),
  smartAction(0x08);

  const ServiceId(this.value);

  final int value;

  static ServiceId fromValue(int value) {
    return ServiceId.values.firstWhere(
      (item) => item.value == value,
      orElse: () => throw ProtocolException(
        'Unsupported service id: 0x${value.toRadixString(16)}',
      ),
    );
  }
}

enum Operation {
  execute(0x01),
  start(0x02),
  stop(0x03),
  set(0x04);

  const Operation(this.value);

  final int value;

  static Operation fromValue(int value) {
    return Operation.values.firstWhere(
      (item) => item.value == value,
      orElse: () => throw ProtocolException(
        'Unsupported operation: 0x${value.toRadixString(16)}',
      ),
    );
  }
}

enum DogBehavior {
  confused(0x01),
  confusedAgain(0x02),
  recoveryBalanceStand1(0x03),
  recoveryBalanceStand(0x04),
  recoveryBalanceStandHigh(0x05),
  forceRecoveryBalanceStand(0x06),
  forceRecoveryBalanceStandHigh(0x07),
  recoveryDanceStandAndParams(0x08),
  recoveryDanceStand(0x09),
  recoveryDanceStandHigh(0x0A),
  recoveryDanceStandHighAndParams(0x0B),
  recoveryDanceStandPose(0x0C),
  recoveryDanceStandHighPose(0x0D),
  recoveryStandPose(0x0E),
  recoveryStandHighPose(0x0F),
  wait(0x10),
  cute(0x11),
  cute2(0x12),
  enjoyTouch(0x13),
  veryEnjoy(0x14),
  eager(0x15),
  excited2(0x16),
  excited(0x17),
  crawl(0x18),
  standAtEase(0x19),
  rest(0x1A),
  shakeSelf(0x1B),
  backFlip(0x1C),
  frontFlip(0x1D),
  leftFlip(0x1E),
  rightFlip(0x1F),
  expressAffection(0x20),
  yawn(0x21),
  danceInPlace(0x22),
  shakeHand(0x23),
  waveHand(0x24),
  drawHeart(0x25),
  pushUp(0x26),
  bow(0x27);

  const DogBehavior(this.value);

  final int value;

  static DogBehavior fromValue(int value) {
    return DogBehavior.values.firstWhere(
      (item) => item.value == value,
      orElse: () => throw ProtocolException(
        'Unsupported dog behavior id: 0x${value.toRadixString(16)}',
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
