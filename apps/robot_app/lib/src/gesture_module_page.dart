import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

class GestureModulePage extends StatefulWidget {
  const GestureModulePage({super.key, required this.client});

  final RobotClient client;

  @override
  State<GestureModulePage> createState() => _GestureModulePageState();
}

class _GestureModulePageState extends State<GestureModulePage> {
  final HandGestureSdk _sdk = HandGestureSdk.instance;
  StreamSubscription<HandGestureEvent>? _gestureSubscription;
  StreamSubscription<HandGestureEvent>? _poseSubscription;
  StreamSubscription<HandGestureEvent>? _statusSubscription;
  StreamSubscription<HandGestureCommand>? _commandSubscription;
  StreamSubscription<RobotConnectionState>? _connectionSubscription;
  final List<HandGestureEvent> _gestureEvents = <HandGestureEvent>[];
  final List<HandGestureEvent> _poseEvents = <HandGestureEvent>[];
  final List<HandGestureCommand> _commands = <HandGestureCommand>[];
  String _latestGesture = '暂无';
  String _latestGestureDiagnostics = '暂无';
  String _latestPose = '暂无';
  String _latestPoseDiagnostics = '暂无';
  String _latestCommand = '暂无';
  String _latestRobotDispatch = '暂无';
  String _gestureMode = GestureControlMode.command.name;
  String _status = '尚未启动';
  late RobotConnectionState _connection = widget.client.currentConnection;
  DateTime? _lastFollowMoveAt;
  int _discreteMoveToken = 0;

  @override
  void initState() {
    super.initState();
    _gestureSubscription = _sdk.gestureEvents.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _gestureEvents.insert(0, event);
        if (event.gesture != null && event.gesture!.isNotEmpty) {
          _latestGesture = event.gesture!;
        } else {
          _latestGesture = event.message;
        }
        _latestGestureDiagnostics = _formatGestureDiagnostics(event);
      });
      unawaited(_syncRecognitionDebugInfo());
    });
    _poseSubscription = _sdk.poseEvents.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _poseEvents.insert(0, event);
        if (event.pose != null && event.pose!.isNotEmpty) {
          _latestPose = event.pose!;
        } else {
          _latestPose = event.message;
        }
        _latestPoseDiagnostics = _formatPoseDiagnostics(event);
      });
      unawaited(_syncRecognitionDebugInfo());
    });
    _statusSubscription = _sdk.statusEvents.listen((event) {
      if (!mounted) {
        return;
      }
      if (event.type == 'closed') {
        unawaited(_restoreOrientations());
      }
      setState(() {
        _status = event.message.isEmpty ? event.type : event.message;
      });
      unawaited(_syncRecognitionDebugInfo());
    });
    _commandSubscription = _sdk.commands.listen((command) {
      if (!mounted) {
        return;
      }
      final mode = command.mode;
      setState(() {
        _commands.insert(0, command);
        _latestCommand = command.message;
        if (mode != null && mode.isNotEmpty) {
          _gestureMode = mode;
        }
      });
      unawaited(_syncRecognitionDebugInfo());
      unawaited(_applyRobotCommand(command));
    });
    _connectionSubscription = widget.client.connectionState.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _connection = state;
      });
      unawaited(_syncRecognitionDebugInfo());
    });
    unawaited(_syncRecognitionDebugInfo());
  }

  @override
  void dispose() {
    _gestureSubscription?.cancel();
    _poseSubscription?.cancel();
    _statusSubscription?.cancel();
    _commandSubscription?.cancel();
    _connectionSubscription?.cancel();
    unawaited(_restoreOrientations());
    super.dispose();
  }

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _openRecognition() async {
    if (!_isSupportedPlatform) {
      setState(() {
        _status = '当前仅支持 Android / iOS';
      });
      return;
    }
    await _sdk.startRecognition();
    unawaited(_syncRecognitionDebugInfo());
  }

  Future<void> _closeRecognition() async {
    if (!_isSupportedPlatform) {
      return;
    }
    await _sdk.stopRecognition();
    await _restoreOrientations();
  }

  Future<void> _restoreOrientations() {
    return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _applyRobotCommand(HandGestureCommand command) async {
    try {
      switch (command.type) {
        case HandGestureCommandType.move:
          if (command.source == 'follow') {
            final didSend = await _sendFollowMove(command);
            if (didSend) {
              _markRobotDispatch(_formatMoveDispatch(command));
            }
          } else {
            await _sendDiscreteMove(command);
          }
          break;
        case HandGestureCommandType.stop:
          _discreteMoveToken++;
          await widget.client.move(0, 0, 0);
          _markRobotDispatch('已下发零速停止 move(0, 0, 0)');
          break;
        case HandGestureCommandType.stand:
          _discreteMoveToken++;
          await widget.client.stand();
          _markRobotDispatch('已下发 stand');
          break;
        case HandGestureCommandType.sit:
          _discreteMoveToken++;
          await widget.client.sit();
          _markRobotDispatch('已下发 sit');
          break;
        case HandGestureCommandType.modeChanged:
          _discreteMoveToken++;
          _lastFollowMoveAt = null;
          _markRobotDispatch('模式切换，不下发运动命令');
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(command.message)),
          );
          break;
        case HandGestureCommandType.follow:
        case HandGestureCommandType.unknown:
          break;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '手势控制下发失败：$error';
        _latestRobotDispatch = '下发失败：$error';
      });
      unawaited(_syncRecognitionDebugInfo());
    }
  }

  void _markRobotDispatch(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _latestRobotDispatch = '$message；连接=${_formatConnection(_connection)}';
    });
    unawaited(_syncRecognitionDebugInfo());
  }

  Future<void> _syncRecognitionDebugInfo() {
    return _sdk.updateRecognitionDebugInfo(<String, String>{
      'mode': _gestureMode,
      'connection': _formatConnection(_connection),
      'status': _status,
      'latestGesture': _latestGesture,
      'latestPose': _latestPose,
      'latestCommand': _latestCommand,
      'latestDispatch': _latestRobotDispatch,
      'gestureDiagnostics': _latestGestureDiagnostics,
      'poseDiagnostics': _latestPoseDiagnostics,
    });
  }

  String _formatGestureDiagnostics(HandGestureEvent event) {
    final metrics = event.metrics ?? const <String, dynamic>{};
    final confidence = event.confidence;
    final centerX = _toDouble(metrics['handCenterX']);
    final centerY = _toDouble(metrics['handCenterY']);
    final area = _toDouble(metrics['handBBoxArea']);
    final side = centerX == null
        ? 'unknown'
        : centerX < 0.45
            ? 'left'
            : centerX > 0.55
                ? 'right'
                : 'center';
    return 'conf=${_formatNullable(confidence)} '
        'center=(${_formatNullable(centerX)},${_formatNullable(centerY)}) '
        'area=${_formatNullable(area)} side=$side';
  }

  String _formatPoseDiagnostics(HandGestureEvent event) {
    final metrics = event.metrics ?? const <String, dynamic>{};
    final confidence = event.confidence;
    final leftKnee = _toDouble(metrics['leftKneeAngle']);
    final rightKnee = _toDouble(metrics['rightKneeAngle']);
    final leftHip = _toDouble(metrics['leftHipAngle']);
    final rightHip = _toDouble(metrics['rightHipAngle']);
    return 'conf=${_formatNullable(confidence)} '
        'knee=(${_formatNullable(leftKnee)},${_formatNullable(rightKnee)}) '
        'hip=(${_formatNullable(leftHip)},${_formatNullable(rightHip)})';
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  String _formatNullable(double? value) {
    if (value == null) {
      return '-';
    }
    return value.toStringAsFixed(2);
  }

  String _formatMoveDispatch(HandGestureCommand command) {
    return '已下发 move(${_formatVelocity(command.vx ?? 0)}, '
        '${_formatVelocity(command.vy ?? 0)}, '
        '${_formatVelocity(command.yaw ?? 0)})';
  }

  String _formatVelocity(double value) {
    return value.toStringAsFixed(2);
  }

  String _formatConnection(RobotConnectionState state) {
    final base = '${state.transport.name}/${state.status.name}';
    final error = state.errorMessage;
    if (error == null || error.isEmpty) {
      return base;
    }
    return '$base ($error)';
  }

  Future<bool> _sendFollowMove(HandGestureCommand command) async {
    final now = DateTime.now();
    final lastSentAt = _lastFollowMoveAt;
    if (lastSentAt != null &&
        now.difference(lastSentAt) < const Duration(milliseconds: 100)) {
      return false;
    }
    _lastFollowMoveAt = now;
    await widget.client
        .move(command.vx ?? 0, command.vy ?? 0, command.yaw ?? 0);
    return true;
  }

  Future<void> _sendDiscreteMove(HandGestureCommand command) async {
    final token = ++_discreteMoveToken;
    await widget.client
        .move(command.vx ?? 0, command.vy ?? 0, command.yaw ?? 0);
    _markRobotDispatch(_formatMoveDispatch(command));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (token == _discreteMoveToken) {
      await widget.client.move(0, 0, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EC),
      appBar: AppBar(
        title: const Text('手势识别模块'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '独立模块方式接入 hand_gesture_sdk，打开后会启动识别页并输出手势 / 动作命令流。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF4B6B66),
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _isSupportedPlatform ? _openRecognition : null,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('打开识别页'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSupportedPlatform ? _closeRecognition : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('关闭识别页'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _InfoCard(
                title: '当前状态',
                value: _status,
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '手势模式',
                value: _gestureMode,
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '机器人连接',
                value: _formatConnection(_connection),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '最新手势',
                value: '$_latestGesture\n$_latestGestureDiagnostics',
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '最新姿态',
                value: '$_latestPose\n$_latestPoseDiagnostics',
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '最新命令',
                value: _latestCommand,
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '最近下发',
                value: _latestRobotDispatch,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _EventStreamPanel(
                  gestureEvents: _gestureEvents,
                  poseEvents: _poseEvents,
                  commands: _commands,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventStreamPanel extends StatelessWidget {
  const _EventStreamPanel({
    required this.gestureEvents,
    required this.poseEvents,
    required this.commands,
  });

  final List<HandGestureEvent> gestureEvents;
  final List<HandGestureEvent> poseEvents;
  final List<HandGestureCommand> commands;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF183936),
        );
    return DefaultTabController(
      length: 3,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('事件流', style: titleStyle),
            ),
            const TabBar(
              isScrollable: true,
              labelColor: Color(0xFF183936),
              unselectedLabelColor: Color(0xFF4B6B66),
              indicatorColor: Color(0xFF183936),
              tabs: <Widget>[
                Tab(text: '手势'),
                Tab(text: '姿态'),
                Tab(text: '命令'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _EventList<HandGestureEvent>(
                    items: gestureEvents,
                    builder: (event) =>
                        '[${event.type}] ${event.message}'
                        '${event.gesture == null ? '' : ' | ${event.gesture}'}',
                  ),
                  _EventList<HandGestureEvent>(
                    items: poseEvents,
                    builder: (event) =>
                        '[${event.type}] ${event.message}'
                        '${event.pose == null ? '' : ' | ${event.pose}'}',
                  ),
                  _EventList<HandGestureCommand>(
                    items: commands,
                    builder: (command) =>
                        '[${command.type.name}] ${command.message}'
                        '${command.gesture == null ? '' : ' | ${command.gesture}'}'
                        '${command.pose == null ? '' : ' | ${command.pose}'}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventList<T> extends StatelessWidget {
  const _EventList({required this.items, required this.builder});

  final List<T> items;
  final String Function(T) builder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无事件'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) => Text(builder(items[index])),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF4B6B66),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF183936),
                ),
          ),
        ],
      ),
    );
  }
}
