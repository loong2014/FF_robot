import 'connection_state.dart';

enum BlePluginLicense { free, commercial }

class BleConnectionOptions {
  static const String defaultServiceUuid =
      '12345678-1234-5678-1234-56789abc0000';
  static const String defaultCmdCharacteristicUuid =
      '12345678-1234-5678-1234-56789abc0001';
  static const String defaultStateCharacteristicUuid =
      '12345678-1234-5678-1234-56789abc0002';

  const BleConnectionOptions({
    this.deviceId = '',
    this.serviceUuid = defaultServiceUuid,
    this.cmdCharacteristicUuid = defaultCmdCharacteristicUuid,
    this.stateCharacteristicUuid = defaultStateCharacteristicUuid,
    this.timeout = const Duration(seconds: 15),
    this.mtuRequest = 0,
    this.pluginLicense = BlePluginLicense.free,
    this.postConnectSettleDelay = const Duration(milliseconds: 300),
  });

  final String deviceId;
  final String serviceUuid;
  final String cmdCharacteristicUuid;
  final String stateCharacteristicUuid;
  final Duration timeout;

  /// BLE ATT MTU 请求值。
  ///
  /// 默认 ``0`` 表示**跳过**显式 ``requestMtu``：Android framework 在 GATT
  /// connect 成功后会自己发一次 ATT Exchange MTU Request，central 再主动发
  /// 一次是协议层禁止的"重复 exchange"，部分 BlueZ 5.53 外设（机器狗上
  /// observed）在处理第二次 Exchange MTU 时会 SEGV，表现为 connect 后几
  /// 秒 ``LINK_SUPERVISION_TIMEOUT``、``FlutterBluePlusException:
  /// discoverServices \| fbp-code: 6 \| device is not connected``。
  ///
  /// iOS 从不接受主动 MTU 请求，无论此值多少都走协商。
  ///
  /// 仅在确认外设允许重复 Exchange MTU、且确实需要覆盖 Android framework
  /// 默认值（通常已协商到 517）时再把它设回 ``247`` / ``517``。
  final int mtuRequest;
  final BlePluginLicense pluginLicense;

  /// GATT 物理连接成功后，发起 requestMtu / discoverServices 之前的等待
  /// 时间。给 Android 协议栈一点时间完成 connection parameter update，
  /// 降低 `LINK_SUPERVISION_TIMEOUT` 概率。
  final Duration postConnectSettleDelay;
}

class TcpConnectionOptions {
  const TcpConnectionOptions({
    this.host = '127.0.0.1',
    this.port = 9000,
    this.connectTimeout = const Duration(seconds: 5),
  });

  final String host;
  final int port;
  final Duration connectTimeout;
}

class MqttConnectionOptions {
  const MqttConnectionOptions({
    this.host = '127.0.0.1',
    this.port = 1883,
    this.robotId = 'dog-001',
    this.clientId = '',
    this.username,
    this.password,
    this.keepAlive = const Duration(seconds: 60),
    this.connectTimeout = const Duration(seconds: 5),
    this.useTls = false,
    this.qos = MqttQosLevel.atLeastOnce,
    this.subscribeEvents = true,
  });

  final String host;
  final int port;
  final String robotId;

  /// Optional. If left empty, `mobile-sdk-<robotId>-<nonce>` is used by
  /// [MqttTransport] at connect-time.
  final String clientId;

  final String? username;
  final String? password;
  final Duration keepAlive;
  final Duration connectTimeout;
  final bool useTls;
  final MqttQosLevel qos;

  /// Whether the transport subscribes to the JSON event topic in
  /// addition to the binary state topic. Off by default for paranoid
  /// clients that do not want to receive unstructured events.
  final bool subscribeEvents;

  String get controlTopic => 'robot/$robotId/control';
  String get stateTopic => 'robot/$robotId/state';
  String get eventTopic => 'robot/$robotId/event';
}

enum MqttQosLevel { atMostOnce, atLeastOnce, exactlyOnce }

class RobotConnectionConfig {
  const RobotConnectionConfig({
    this.priority = const <TransportKind>[
      TransportKind.ble,
      TransportKind.tcp,
      TransportKind.mqtt,
    ],
    this.ble,
    this.tcp,
    this.mqtt,
  });

  final List<TransportKind> priority;
  final BleConnectionOptions? ble;
  final TcpConnectionOptions? tcp;
  final MqttConnectionOptions? mqtt;
}
