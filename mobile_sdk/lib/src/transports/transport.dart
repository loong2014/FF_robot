import 'dart:typed_data';

import 'package:robot_protocol/robot_protocol.dart';

abstract class RobotTransport {
  Stream<RobotFrame> get frames;

  bool get isConnected;

  Future<void> connect();

  Future<void> disconnect();

  Future<void> send(Uint8List bytes);
}
