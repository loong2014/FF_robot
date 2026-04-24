import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

import 'action_engine.dart';
import 'action_models.dart';
import 'action_program_view.dart';
import 'ble_scan_page.dart';
import 'mqtt_connect_dialog.dart';
import 'quick_control_panel.dart';
import 'tcp_connect_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final RobotClient _client = RobotClient();
  late final ActionEngine _engine = ActionEngine(_client);
  late final List<ActionStep> _initialProgram = <ActionStep>[
    ActionStep.stand(),
    ActionStep.doDogBehavior(behavior: DogBehavior.waveHand),
    ActionStep.move(
      vx: 0.35,
      yaw: 0.15,
      duration: const Duration(seconds: 1),
    ),
    ActionStep.doAction(actionId: 20593),
    ActionStep.sit(),
  ];

  StreamSubscription<RobotState>? _stateSubscription;
  StreamSubscription<RobotFrame>? _frameSubscription;
  StreamSubscription<ActionEngineStatus>? _statusSubscription;
  StreamSubscription<RobotConnectionState>? _connectionSubscription;
  StreamSubscription<Object>? _errorSubscription;
  RobotState? _latestState;
  DateTime? _lastStateAt;
  int _stateFrameCount = 0;
  int? _lastStateSeq;
  String? _lastStatePayloadHex;
  String? _lastStateFrameHex;
  ActionEngineStatus _status = ActionEngineStatus.idle;
  RobotConnectionState _connection = RobotConnectionState.idle();
  String? _connectedBleDeviceName;
  TcpConnectionOptions _lastTcpOptions = const TcpConnectionOptions();
  MqttConnectionOptions _lastMqttOptions = const MqttConnectionOptions();

  @override
  void initState() {
    super.initState();
    _stateSubscription = _client.stateStream.listen((state) {
      setState(() {
        _latestState = state;
      });
    });
    _frameSubscription = _client.frameStream.listen((frame) {
      if (frame.type != FrameType.state) {
        return;
      }
      setState(() {
        _stateFrameCount += 1;
        _lastStateAt = DateTime.now();
        _lastStateSeq = frame.seq;
        _lastStatePayloadHex = _formatHex(frame.payload);
        _lastStateFrameHex = _formatHex(encodeFrame(frame));
      });
    });
    _statusSubscription = _engine.statusStream.listen((status) {
      setState(() {
        _status = status;
      });
    });
    _connectionSubscription = _client.connectionState.listen((state) {
      setState(() {
        _connection = state;
        if (state.transport != TransportKind.ble) {
          _connectedBleDeviceName = null;
        }
      });
    });
    _errorSubscription = _client.errors.listen((error) {
      if (!mounted) {
        return;
      }
      _showMessage('运行时错误: $error');
    });
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_frameSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_engine.dispose());
    unawaited(_client.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _latestState;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFF5F2E8),
              Color(0xFFE3F0EC),
              Color(0xFFD9E9F4),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.hasBoundedHeight
                        ? math.max(0, constraints.maxHeight - 40)
                        : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Robot OS Lite',
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF153B37),
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '机器狗控制台 / 图形化动作编排',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF2F5D58),
                            ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _ControlCard(
                            title: '连接',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _ConnectionBadge(
                                  connection: _connection,
                                  bleDeviceName: _connectedBleDeviceName,
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    FilledButton.icon(
                                      onPressed: _isConnectingOrConnected
                                          ? null
                                          : _connectBle,
                                      icon: const Icon(
                                        Icons.bluetooth_searching,
                                        size: 18,
                                      ),
                                      label: const Text('连接机器人 (BLE)'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _connection.status ==
                                              ConnectionStatus.idle
                                          ? null
                                          : _disconnect,
                                      icon: const Icon(
                                        Icons.link_off,
                                        size: 18,
                                      ),
                                      label: const Text('断开'),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: '高级连接',
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'tcp':
                                            _connectTcp();
                                            break;
                                          case 'mqtt':
                                            _connectMqtt();
                                            break;
                                        }
                                      },
                                      itemBuilder: (_) =>
                                          const <PopupMenuEntry<String>>[
                                        PopupMenuItem<String>(
                                          value: 'tcp',
                                          child: Text('使用 TCP 连接'),
                                        ),
                                        PopupMenuItem<String>(
                                          value: 'mqtt',
                                          child: Text('使用 MQTT 连接'),
                                        ),
                                      ],
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Icon(
                                              Icons.more_horiz,
                                              size: 18,
                                              color: Color(0xFF2F5D58),
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              '高级连接',
                                              style: TextStyle(
                                                color: Color(0xFF2F5D58),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _ControlCard(
                            title: '快捷控制',
                            child: QuickControlPanel(
                              client: _client,
                              isConnected: _connection.status ==
                                  ConnectionStatus.connected,
                              onRequireConnection: _promptConnectBle,
                              onMessage: _showMessage,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _StatusPanel(
                        connection: _connection,
                        bleDeviceName: _connectedBleDeviceName,
                        tcpOptions: _lastTcpOptions,
                        mqttOptions: _lastMqttOptions,
                        status: _status,
                        state: state,
                      ),
                      const SizedBox(height: 20),
                      _ReceivedDataPanel(
                        state: state,
                        stateFrameCount: _stateFrameCount,
                        lastStateAt: _lastStateAt,
                        lastStateSeq: _lastStateSeq,
                        lastStatePayloadHex: _lastStatePayloadHex,
                        lastStateFrameHex: _lastStateFrameHex,
                      ),
                      const SizedBox(height: 20),
                      ActionProgramView(
                        engine: _engine,
                        initialProgram: _initialProgram,
                        isConnected:
                            _connection.status == ConnectionStatus.connected,
                        onRequireConnection: _promptConnectBle,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool get _isConnectingOrConnected {
    final status = _connection.status;
    return status == ConnectionStatus.connecting ||
        status == ConnectionStatus.connected ||
        status == ConnectionStatus.reconnecting;
  }

  Future<void> _promptConnectBle() async {
    _showMessage('请先通过 BLE 连接机器人');
    await _connectBle();
  }

  Future<void> _connectTcp() async {
    final options = await showTcpConnectDialog(
      context: context,
      initial: _lastTcpOptions,
    );
    if (!mounted || options == null) {
      return;
    }

    setState(() {
      _lastTcpOptions = options;
    });

    try {
      await _client.connectTCP(options: options);
      _showMessage('TCP 已连接到 ${options.host}:${options.port}');
    } catch (error) {
      _showMessage('TCP 连接失败: $error');
    }
  }

  Future<void> _connectBle() async {
    final device = await Navigator.of(context).push<BleDiscoveredDevice>(
      MaterialPageRoute<BleDiscoveredDevice>(
        builder: (_) => BleScanPage(client: _client),
      ),
    );
    if (!mounted || device == null) {
      return;
    }

    try {
      await _client.connectBLE(
        options: BleConnectionOptions(deviceId: device.id),
      );
      setState(() {
        _connectedBleDeviceName = device.name;
      });
      _showMessage('BLE 已连接到 ${device.name}');
    } catch (error) {
      _showMessage(_describeBleError(error));
    }
  }

  String _describeBleError(Object error) {
    if (error is BleConnectException) {
      final causeText = error.cause.toString();
      switch (error.stage) {
        case BleConnectStage.gattConnect:
          if (causeText.contains('CONNECTION_FAILED_ESTABLISHMENT')) {
            return 'BLE 物理连接建立失败（Android GATT status=62）。\n'
                '请先确认蓝牙调试助手或其他 App 已完全断开该设备，然后重试一次；'
                '如果机器狗刚结束广播扫描，等待 1-2 秒再连更稳定。\n'
                '原始错误: ${error.cause}';
          }
          return 'BLE 物理连接失败（GATT 未握手成功或链路刚建立即断开）。'
              '常见原因：机器人端 bluetoothd 未就绪 / 信号弱 / 固件不响应 MTU 协商。\n'
              '原始错误: ${error.cause}';
        case BleConnectStage.discoverServices:
          return 'BLE 已连接，但未找到机器人服务（service/characteristic）。\n'
              '请确认机器狗上运行的是本项目 robot_server 的 BLE 后端'
              '（广播 RobotOSLite），而不是厂商 ble_gatt_server。\n'
              '原始错误: ${error.cause}';
        case BleConnectStage.subscribeState:
          return 'BLE 服务已发现，但订阅 state 通知失败。'
              '请检查 state characteristic 是否支持 notify。\n'
              '原始错误: ${error.cause}';
      }
    }
    return 'BLE 连接失败: $error';
  }

  Future<void> _connectMqtt() async {
    final options = await showMqttConnectDialog(
      context: context,
      initial: _lastMqttOptions,
    );
    if (!mounted || options == null) {
      return;
    }

    setState(() {
      _lastMqttOptions = options;
    });

    try {
      await _client.connectMQTT(options: options);
      _showMessage(
        'MQTT 已连接到 ${options.host}:${options.port} (robot=${options.robotId})',
      );
    } catch (error) {
      _showMessage('MQTT 连接失败: $error');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _client.disconnect();
      _showMessage('已断开连接');
    } catch (error) {
      _showMessage('断开失败: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatHex(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, 12),
            color: Color(0x220F3D38),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF183936),
                ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({
    required this.connection,
    required this.bleDeviceName,
  });

  final RobotConnectionState connection;
  final String? bleDeviceName;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _style();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  (Color, String, IconData) _style() {
    final transportLabel = _transportLabel(connection.transport);
    final device = bleDeviceName;
    switch (connection.status) {
      case ConnectionStatus.connected:
        final suffix = device != null && device.isNotEmpty
            ? ' · $device'
            : (connection.transport != TransportKind.none
                ? ' · $transportLabel'
                : '');
        return (
          const Color(0xFF2E7D32),
          '已连接$suffix',
          Icons.check_circle,
        );
      case ConnectionStatus.connecting:
        return (
          const Color(0xFF1F7A6F),
          '连接中... ($transportLabel)',
          Icons.sync,
        );
      case ConnectionStatus.reconnecting:
        return (
          const Color(0xFFB7791F),
          '重连中... ($transportLabel)',
          Icons.autorenew,
        );
      case ConnectionStatus.failed:
        return (
          const Color(0xFFB23A48),
          '连接失败 (${connection.errorCode ?? 'unknown'})',
          Icons.error_outline,
        );
      case ConnectionStatus.idle:
        return (const Color(0xFF6B8682), '未连接', Icons.link_off);
    }
  }

  static String _transportLabel(TransportKind kind) {
    switch (kind) {
      case TransportKind.none:
        return 'None';
      case TransportKind.ble:
        return 'BLE';
      case TransportKind.tcp:
        return 'TCP';
      case TransportKind.mqtt:
        return 'MQTT';
    }
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.connection,
    required this.bleDeviceName,
    required this.tcpOptions,
    required this.mqttOptions,
    required this.status,
    required this.state,
  });

  final RobotConnectionState connection;
  final String? bleDeviceName;
  final TcpConnectionOptions tcpOptions;
  final MqttConnectionOptions mqttOptions;
  final ActionEngineStatus status;
  final RobotState? state;

  @override
  Widget build(BuildContext context) {
    final robotState = state;
    final rows = <String>[
      'Link    : ${_describeConnection(connection)}',
      'BLE     : ${bleDeviceName ?? '--'}',
      'TCP cfg : ${tcpOptions.host}:${tcpOptions.port}',
      'MQTT cfg: ${mqttOptions.host}:${mqttOptions.port} / ${mqttOptions.robotId}'
          '${mqttOptions.useTls ? ' (TLS)' : ''}',
      'Engine  : ${status.name}',
      'Battery : ${robotState?.battery ?? '--'}',
      'Roll    : ${robotState?.roll.toStringAsFixed(2) ?? '--'}',
      'Pitch   : ${robotState?.pitch.toStringAsFixed(2) ?? '--'}',
      'Yaw     : ${robotState?.yaw.toStringAsFixed(2) ?? '--'}',
    ];
    if (connection.errorCode != null) {
      rows.add(
          'Err     : ${connection.errorCode} / ${connection.errorMessage ?? ''}');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF173C38),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Text(
        rows.join('\n'),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              color: const Color(0xFFEAF4F1),
              height: 1.6,
            ),
      ),
    );
  }

  String _describeConnection(RobotConnectionState state) {
    final transport = _describeTransport(state.transport);
    final status = state.status.name;
    return '$transport / $status';
  }

  String _describeTransport(TransportKind kind) {
    switch (kind) {
      case TransportKind.none:
        return 'Disconnected';
      case TransportKind.ble:
        return 'BLE';
      case TransportKind.tcp:
        return 'TCP';
      case TransportKind.mqtt:
        return 'MQTT';
    }
  }
}

class _ReceivedDataPanel extends StatelessWidget {
  const _ReceivedDataPanel({
    required this.state,
    required this.stateFrameCount,
    required this.lastStateAt,
    required this.lastStateSeq,
    required this.lastStatePayloadHex,
    required this.lastStateFrameHex,
  });

  final RobotState? state;
  final int stateFrameCount;
  final DateTime? lastStateAt;
  final int? lastStateSeq;
  final String? lastStatePayloadHex;
  final String? lastStateFrameHex;

  @override
  Widget build(BuildContext context) {
    final hasData = state != null && stateFrameCount > 0;
    final robotState = state;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, 12),
            color: Color(0x1F103E38),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '最近收到的数据',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF183936),
                ),
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Text(
              '尚未收到机器人状态帧。连接成功后，服务端推送的 STATE 数据会显示在这里。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4E6A66),
                    height: 1.6,
                  ),
            )
          else ...<Widget>[
            SelectableText(
              <String>[
                'Frames  : $stateFrameCount',
                'At      : ${_formatTime(lastStateAt!)}',
                'Seq     : ${lastStateSeq ?? '--'}',
                'Battery : ${robotState!.battery}',
                'Roll    : ${robotState.roll.toStringAsFixed(2)}',
                'Pitch   : ${robotState.pitch.toStringAsFixed(2)}',
                'Yaw     : ${robotState.yaw.toStringAsFixed(2)}',
              ].join('\n'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontFamily: 'monospace',
                    color: const Color(0xFF173C38),
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Payload Hex',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF244842),
                  ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              lastStatePayloadHex ?? '--',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: const Color(0xFF355A54),
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Frame Hex',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF244842),
                  ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              lastStateFrameHex ?? '--',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: const Color(0xFF355A54),
                    height: 1.6,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    String three(int part) => part.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.'
        '${three(value.millisecond)}';
  }
}
