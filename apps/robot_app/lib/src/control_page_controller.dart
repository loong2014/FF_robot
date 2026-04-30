import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

import 'control_actions.dart';

class ControlPageController extends ChangeNotifier {
  ControlPageController({
    required RobotClient client,
    this.initialBleDeviceName,
  }) : _client = client {
    _connectionSubscription = _client.connectionState.listen((state) {
      final wasBleConnected = isBleConnected;
      _connection = state;
      final connectedNow = isBleConnected;
      if (state.transport != TransportKind.ble) {
        _bleDeviceName = null;
      }
      if (!connectedNow) {
        _stopJoystickTimer();
        _leftDx = 0;
        _leftDy = 0;
        _rightDx = 0;
        _joystickSessionActive = false;
        _resetMotionModeState();
        if (wasBleConnected && state.transport == TransportKind.ble) {
          _lastAction = 'BLE 已断开，已停止发送遥控命令';
        }
      } else if (!wasBleConnected) {
        _resetMotionModeState();
        _lastAction = 'BLE 已连接，摇杆会重新进入运动模式';
      }
      notifyListeners();
    });
    _stateSubscription = _client.stateStream.listen((state) {
      _batteryPercent = state.battery;
      notifyListeners();
    });
    _errorSubscription = _client.errors.listen((_) {
      _resetMotionModeState();
      if (_joystickSessionActive) {
        _lastAction = '控制命令失败，摇杆会重新进入运动模式';
        notifyListeners();
      }
    });
  }

  static const Duration _joystickInterval = Duration(milliseconds: 100);
  static const double _maxLinearSpeed = 0.65;
  static const double _maxYawSpeed = 0.9;
  static const double _deadZone = 0.08;

  final RobotClient _client;
  final String? initialBleDeviceName;

  StreamSubscription<RobotConnectionState>? _connectionSubscription;
  StreamSubscription<RobotState>? _stateSubscription;
  StreamSubscription<Object>? _errorSubscription;
  Timer? _joystickTimer;

  RobotConnectionState _connection = RobotConnectionState.idle();
  int _batteryPercent = -1;
  String _lastAction = '';
  String? _bleDeviceName;
  bool _emergencyStopped = false;
  bool _motionModeReady = false;
  Future<void>? _motionModeFuture;
  int _motionModeGeneration = 0;
  bool _joystickSessionActive = false;
  double _leftDx = 0;
  double _leftDy = 0;
  double _rightDx = 0;

  RobotConnectionState get connection => _connection;
  int get batteryPercent => _batteryPercent;
  String get lastAction => _lastAction;
  String? get bleDeviceName => _bleDeviceName ?? initialBleDeviceName;
  bool get isEmergencyStopped => _emergencyStopped;
  bool get isBleConnected =>
      _connection.status == ConnectionStatus.connected &&
      _connection.transport == TransportKind.ble;
  bool get isBleBusy =>
      _connection.transport == TransportKind.ble &&
      (_connection.status == ConnectionStatus.connecting ||
          _connection.status == ConnectionStatus.reconnecting);

  Future<void> connectBle({
    required BleConnectionOptions options,
    String? deviceName,
  }) async {
    await _client.connectBLE(options: options);
    _bleDeviceName = deviceName;
    _lastAction = 'BLE 已连接';
    notifyListeners();
  }

  Future<void> disconnect() async {
    _stopJoystickTimer();
    _leftDx = 0;
    _leftDy = 0;
    _rightDx = 0;
    _joystickSessionActive = false;
    _resetMotionModeState();
    _emergencyStopped = false;
    await _client.disconnect();
    _lastAction = '已断开连接';
    notifyListeners();
  }

  void updateMovement({required double dx, required double dy}) {
    if (_emergencyStopped) {
      return;
    }
    _leftDx = _applyDeadZone(dx);
    _leftDy = _applyDeadZone(dy);
    _startJoystickTimer();
  }

  void updateRotation({required double dx}) {
    if (_emergencyStopped) {
      return;
    }
    _rightDx = _applyDeadZone(dx);
    _startJoystickTimer();
  }

  Future<void> stopJoystick() async {
    _stopJoystickTimer();
    _leftDx = 0;
    _leftDy = 0;
    _rightDx = 0;
    _joystickSessionActive = false;
    _resetMotionModeState();
    if (isBleConnected && !_emergencyStopped) {
      await _client.move(0, 0, 0);
    }
    notifyListeners();
  }

  Future<void> triggerAction(ControlAction action) async {
    if (!isBleConnected) {
      throw StateError('请先通过 BLE 连接机器人');
    }

    switch (action.kind) {
      case ControlActionKind.stand:
        await _client.stand();
        break;
      case ControlActionKind.sit:
        await _client.sit();
        break;
      case ControlActionKind.stop:
        await _client.stop();
        break;
      case ControlActionKind.dogBehavior:
        await _client.doDogBehavior(action.behavior!);
        break;
      case ControlActionKind.actionId:
        await _client.doAction(action.actionId!);
        break;
    }

    _lastAction = action.label;
    notifyListeners();
  }

  Future<void> emergencyStop() async {
    if (!isBleConnected) {
      throw StateError('请先通过 BLE 连接机器人');
    }
    _emergencyStopped = true;
    _resetMotionModeState();
    _stopJoystickTimer();
    _leftDx = 0;
    _leftDy = 0;
    _rightDx = 0;
    _joystickSessionActive = false;
    await _client.emergencyStop();
    _lastAction = '急停';
    notifyListeners();
  }

  Future<void> recoverEmergencyStop() async {
    if (!isBleConnected) {
      throw StateError('请先通过 BLE 连接机器人');
    }
    _resetMotionModeState();
    await _client.recover();
    _emergencyStopped = false;
    _lastAction = '恢复';
    notifyListeners();
  }

  double _applyDeadZone(double value) {
    if (value.abs() < _deadZone) {
      return 0;
    }
    return value.clamp(-1.0, 1.0);
  }

  void _startJoystickTimer() {
    if (!isBleConnected || _emergencyStopped) {
      return;
    }
    if (!_joystickSessionActive) {
      _joystickSessionActive = true;
      _resetMotionModeState();
    }
    _joystickTimer ??= Timer.periodic(_joystickInterval, (_) {
      unawaited(_sendMove());
    });
    unawaited(_sendMove());
  }

  void _stopJoystickTimer() {
    _joystickTimer?.cancel();
    _joystickTimer = null;
  }

  Future<void> _sendMove() async {
    try {
      if (!isBleConnected || _emergencyStopped) {
        _stopJoystickTimer();
        return;
      }

      await _ensureMotionMode();
      if (!isBleConnected || _emergencyStopped) {
        _stopJoystickTimer();
        return;
      }

      final vx = (_leftDy * _maxLinearSpeed).clamp(
        -_maxLinearSpeed,
        _maxLinearSpeed,
      );
      final vy = (_leftDx * _maxLinearSpeed).clamp(
        -_maxLinearSpeed,
        _maxLinearSpeed,
      );
      final yaw = (-_rightDx * _maxYawSpeed).clamp(
        -_maxYawSpeed,
        _maxYawSpeed,
      );

      await _client.move(vx, vy, yaw);
    } catch (_) {
      _stopJoystickTimer();
      _joystickSessionActive = false;
      _resetMotionModeState();
      _lastAction = '控制命令发送失败';
      notifyListeners();
    }
  }

  Future<void> _ensureMotionMode() async {
    if (!isBleConnected || _emergencyStopped || _motionModeReady) {
      return;
    }

    final pending = _motionModeFuture;
    if (pending != null) {
      await pending;
      return;
    }

    final generation = _motionModeGeneration;
    final future = _client.enterMotionMode().then((_) {
      if (generation == _motionModeGeneration &&
          isBleConnected &&
          !_emergencyStopped) {
        _motionModeReady = true;
        _lastAction = '进入运动模式';
        notifyListeners();
      }
    });
    _motionModeFuture = future;
    try {
      await future;
    } finally {
      if (identical(_motionModeFuture, future)) {
        _motionModeFuture = null;
      }
    }
  }

  void _resetMotionModeState() {
    _motionModeGeneration += 1;
    _motionModeReady = false;
    _motionModeFuture = null;
  }

  @override
  void dispose() {
    _stopJoystickTimer();
    unawaited(_connectionSubscription?.cancel());
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    super.dispose();
  }
}
