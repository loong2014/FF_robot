import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

import 'ble_scan_page.dart';
import 'control_actions.dart';
import 'control_page_controller.dart';
import 'joystick_pad.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({
    super.key,
    required this.client,
    this.initialBleDeviceName,
    this.onBleDeviceConnected,
  });

  final RobotClient client;
  final String? initialBleDeviceName;
  final ValueChanged<BleDiscoveredDevice>? onBleDeviceConnected;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  static const Duration _kEmergencyDoubleTapWindow = Duration(milliseconds: 450);
  static const Duration _kEmergencySingleTapHintDelay = Duration(seconds: 1);
  static const Duration _kToastVisibleDuration = Duration(milliseconds: 1400);

  late final ControlPageController _controller = ControlPageController(
    client: widget.client,
    initialBleDeviceName: widget.initialBleDeviceName,
  );

  Timer? _emergencyHintTimer;
  DateTime? _emergencyFirstTapTime;

  Timer? _toastRemoveTimer;
  OverlayEntry? _toastOverlayEntry;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _emergencyHintTimer?.cancel();
    _toastRemoveTimer?.cancel();
    _toastOverlayEntry?.remove();
    _toastOverlayEntry = null;
    _controller.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: <Widget>[
                  _buildTopBar(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        final sideWidth = (constraints.maxWidth * 0.22).clamp(
                          172.0,
                          280.0,
                        );
                        return Row(
                          children: <Widget>[
                            _buildJoystickPanel(
                              width: sideWidth,
                              label: '移动',
                              onMove: (double dx, double dy) {
                                _controller.updateMovement(dx: dx, dy: dy);
                              },
                              onEnd: _controller.stopJoystick,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _buildActionGrid()),
                            const SizedBox(width: 12),
                            _buildJoystickPanel(
                              width: sideWidth,
                              label: '转向',
                              isRotation: true,
                              showArrows: false,
                              onMove: (double dx, double dy) {
                                _controller.updateRotation(dx: dx);
                              },
                              onEnd: _controller.stopJoystick,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120C2450),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          _TopIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          _TopIconButton(
            icon: _controller.isBleConnected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_searching_rounded,
            foregroundColor: _controller.isBleConnected
                ? const Color(0xFF1F9D64)
                : const Color(0xFF1D2A3A),
            onPressed: _controller.isBleBusy ? null : _connectBle,
          ),
          const SizedBox(width: 8),
          _TopIconButton(
            icon: Icons.tune_rounded,
            onPressed: () {
              _showMessage('当前页面仅保留正式遥控功能');
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  _controller.isBleConnected
                      ? (_controller.bleDeviceName?.isNotEmpty == true
                          ? _controller.bleDeviceName!
                          : 'BLE 已连接')
                      : (_controller.isBleBusy ? 'BLE 连接中…' : '请先连接 BLE'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D2A3A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _controller.lastAction.isNotEmpty
                      ? '最近动作：${_controller.lastAction}'
                      : '当前页控制命令统一走 RobotClient / BLE',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7C8698),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_controller.batteryPercent >= 0) ...<Widget>[
            const Icon(
              Icons.battery_std_rounded,
              size: 20,
              color: Color(0xFF1D2A3A),
            ),
            const SizedBox(width: 4),
            Text(
              '${_controller.batteryPercent}%',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1D2A3A),
              ),
            ),
            const SizedBox(width: 14),
          ],
          SizedBox(
            height: 42,
            child: FilledButton(
              onPressed: _controller.isBleConnected
                  ? _onEmergencyOrRecoverButtonPressed
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _controller.isEmergencyStopped
                    ? const Color(0xFFDFF6E8)
                    : const Color(0xFFFFB5B5),
                foregroundColor: _controller.isEmergencyStopped
                    ? const Color(0xFF1F9D64)
                    : const Color(0xFFD63939),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _controller.isEmergencyStopped ? '恢复' : '急停',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120C2450),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final spacing = constraints.maxWidth > 700 ? 16.0 : 10.0;
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: constraints.maxWidth > 700 ? 0.95 : 0.9,
            ),
            itemCount: kControlActions.length,
            itemBuilder: (BuildContext context, int index) {
              final action = kControlActions[index];
              return _ActionButton(
                label: action.label,
                icon: action.icon,
                enabled: _controller.isBleConnected,
                onTap: () => _triggerAction(action),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildJoystickPanel({
    required double width,
    required String label,
    required void Function(double dx, double dy) onMove,
    required Future<void> Function() onEnd,
    bool showArrows = true,
    bool isRotation = false,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120C2450),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4C5666),
            ),
          ),
          const Spacer(),
          JoystickPad(
            size: (width - 28).clamp(168.0, 224.0),
            onMove: onMove,
            onEnd: () => unawaited(onEnd()),
            showArrows: showArrows,
            isRotation: isRotation,
          ),
          const Spacer(),
          Text(
            _controller.isBleConnected ? '拖动持续控制' : '连接 BLE 后可用',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8D96A6),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectBle() async {
    final device = await Navigator.of(context).push<BleDiscoveredDevice>(
      MaterialPageRoute<BleDiscoveredDevice>(
        builder: (_) => BleScanPage(client: widget.client),
      ),
    );
    if (!mounted || device == null) {
      return;
    }

    try {
      await _controller.connectBle(
        options: BleConnectionOptions(deviceId: device.id),
        deviceName: device.name,
      );
      widget.onBleDeviceConnected?.call(device);
      _showMessage('BLE 已连接到 ${device.name}');
    } catch (error) {
      _showMessage('BLE 连接失败: $error');
    }
  }

  Future<void> _triggerAction(ControlAction action) async {
    try {
      await _controller.triggerAction(action);
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  void _onEmergencyOrRecoverButtonPressed() {
    final DateTime now = DateTime.now();
    if (_emergencyFirstTapTime != null &&
        now.difference(_emergencyFirstTapTime!) <= _kEmergencyDoubleTapWindow) {
      _emergencyHintTimer?.cancel();
      _emergencyHintTimer = null;
      _emergencyFirstTapTime = null;
      if (_controller.isEmergencyStopped) {
        unawaited(_recoverEmergencyStop());
      } else {
        unawaited(_emergencyStop());
      }
      return;
    }
    _emergencyFirstTapTime = now;
    _emergencyHintTimer?.cancel();
    _emergencyHintTimer = Timer(_kEmergencySingleTapHintDelay, () {
      _emergencyHintTimer = null;
      _emergencyFirstTapTime = null;
      if (!mounted) {
        return;
      }
      _showMessage('请双击按钮');
    });
  }

  Future<void> _emergencyStop() async {
    try {
      await _controller.emergencyStop();
      _showMessage('已发送急停');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _recoverEmergencyStop() async {
    try {
      await _controller.recoverEmergencyStop();
      _showMessage('已发送恢复');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    _toastRemoveTimer?.cancel();
    _toastOverlayEntry?.remove();
    _toastOverlayEntry = null;

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext ctx) => IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 88),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE6282830),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _toastOverlayEntry = entry;
    overlay.insert(entry);
    _toastRemoveTimer = Timer(_kToastVisibleDuration, () {
      _toastRemoveTimer = null;
      entry.remove();
      if (_toastOverlayEntry == entry) {
        _toastOverlayEntry = null;
      }
    });
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFF),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            color: foregroundColor ?? const Color(0xFF1D2A3A),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFCFDFF),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6EDF8)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 28,
                color:
                    enabled ? const Color(0xFF3E86FF) : const Color(0xFFB6C0CF),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: enabled
                      ? const Color(0xFF243040)
                      : const Color(0xFFB6C0CF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
