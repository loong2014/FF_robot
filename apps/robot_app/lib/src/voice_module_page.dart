import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

import 'voice_robot_controller.dart';

class VoiceModulePage extends StatefulWidget {
  const VoiceModulePage({
    required this.controller,
    super.key,
  });

  final VoiceRobotController controller;

  @override
  State<VoiceModulePage> createState() => _VoiceModulePageState();
}

class _VoiceModulePageState extends State<VoiceModulePage> {
  StreamSubscription<VoiceEvent>? _eventSubscription;
  StreamSubscription<String>? _feedbackSubscription;

  final List<VoiceEvent> _events = <VoiceEvent>[];
  VoiceStateEvent? _latestState;
  VoiceWakeEvent? _latestWake;
  VoiceAsrEvent? _latestAsr;
  VoiceCommandEvent? _latestCommand;
  VoiceErrorEvent? _latestError;
  String? _feedback;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _running = widget.controller.isRunning;
    _eventSubscription = widget.controller.events.listen(_handleEvent);
    _feedbackSubscription = widget.controller.feedback.listen((message) {
      if (!mounted) {
        return;
      }
      setState(() {
        _feedback = message;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    super.dispose();
  }

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _start() async {
    if (!_isSupportedPlatform) {
      setState(() {
        _feedback = '当前仅支持 Android / iOS';
      });
      return;
    }

    final granted = await widget.controller.ensurePermissions();
    if (!granted) {
      if (!mounted) {
        return;
      }
      setState(() {
        _feedback = '请先允许麦克风权限；Android 13+ 还需要允许通知权限';
        _running = false;
      });
      return;
    }

    try {
      await widget.controller.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _running = true;
        _latestError = null;
        _feedback = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _running = false;
        _feedback = '启动失败: $error';
      });
    }
  }

  Future<void> _stop() async {
    await widget.controller.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
    });
  }

  void _handleEvent(VoiceEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {
      _events.insert(0, event);
      if (_events.length > 80) {
        _events.removeLast();
      }
      if (event is VoiceStateEvent) {
        _latestState = event;
        _running = event.listening;
        if (event.state != VoiceRecognitionState.error) {
          _latestError = null;
        }
      } else if (event is VoiceWakeEvent) {
        _latestWake = event;
      } else if (event is VoiceAsrEvent) {
        _latestAsr = event;
      } else if (event is VoiceCommandEvent) {
        _latestCommand = event;
      } else if (event is VoiceErrorEvent) {
        _latestError = event;
        _feedback = event.recoveryHint;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2E8),
      appBar: AppBar(title: const Text('语音控制模块')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Text(
              '固定唤醒词 Lumi / 鲁米。启动后进入待唤醒状态，唤醒后识别单条指令并通过当前 RobotClient 下发。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B6B66),
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _isSupportedPlatform && !_running ? _start : null,
                  icon: const Icon(Icons.mic_rounded, size: 18),
                  label: const Text('启动语音服务'),
                ),
                OutlinedButton.icon(
                  onPressed: _running ? _stop : null,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('停止服务'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _StatusCard(
              title: '当前状态',
              value: _stateText(),
              details: _feedback ?? _stateDetails(),
            ),
            const SizedBox(height: 12),
            if (_latestError != null) ...<Widget>[
              _StatusCard(
                title: '恢复建议',
                value: _latestError!.code,
                details: _latestError!.recoveryHint,
                danger: true,
              ),
              const SizedBox(height: 12),
            ],
            _StatusCard(
              title: '最新唤醒',
              value: _latestWake?.recognizedText ?? '暂无',
              details: _latestWake == null
                  ? '等待 Lumi / 鲁米'
                  : '${_latestWake!.wakeWord} · ${_latestWake!.language.wireName} · ${_latestWake!.confidence.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 12),
            _StatusCard(
              title: '最新识别',
              value: _latestAsr == null
                  ? '暂无'
                  : (_latestAsr!.isFinal ? '最终结果' : '实时转写'),
              details: _latestAsr?.text,
            ),
            const SizedBox(height: 12),
            _StatusCard(
              title: '最新命令',
              value: _latestCommand?.command.wireName ?? '暂无',
              details: _latestCommand?.rawText,
            ),
            const SizedBox(height: 20),
            Text(
              '事件流',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF183936),
                  ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 320,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _events.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, index) =>
                    Text(_describe(_events[index])),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stateText() {
    final state = _latestState?.state;
    if (state == null) {
      return _running ? '等待 Lumi / 鲁米 唤醒' : '语音服务已停止';
    }
    switch (state) {
      case VoiceRecognitionState.stopped:
        return '语音服务已停止';
      case VoiceRecognitionState.starting:
        return '正在启动语音控制';
      case VoiceRecognitionState.waitingForWake:
        return '等待 Lumi / 鲁米 唤醒';
      case VoiceRecognitionState.wakeDetected:
        return '已唤醒，请说指令';
      case VoiceRecognitionState.activeListening:
        return '正在识别语音指令';
      case VoiceRecognitionState.processingCommand:
        return '正在处理指令';
      case VoiceRecognitionState.error:
        return '语音控制异常';
    }
  }

  String? _stateDetails() {
    final state = _latestState;
    if (state == null) {
      return _running ? '服务运行中' : '点击启动后进入 waiting_for_wake';
    }
    return '${state.state.wireName} · ${state.engine.wireName}';
  }

  String _describe(VoiceEvent event) {
    if (event is VoiceWakeEvent) {
      return '[wake] ${event.recognizedText} (${event.language.wireName})';
    }
    if (event is VoiceAsrEvent) {
      return '[asr] ${event.isFinal ? "final" : "partial"} | ${event.text}';
    }
    if (event is VoiceCommandEvent) {
      return '[command] ${event.command.wireName} | ${event.rawText}';
    }
    if (event is VoiceStateEvent) {
      return '[state] ${event.state.wireName} | ${event.message}';
    }
    if (event is VoiceErrorEvent) {
      return '[error] ${event.code} | ${event.message}';
    }
    if (event is VoiceTelemetryEvent) {
      return '[telemetry] ${event.message}';
    }
    return '[event] ${event.type}';
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    this.details,
    this.danger = false,
  });

  final String title;
  final String value;
  final String? details;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : const Color(0xFF183936);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border:
            danger ? Border.all(color: color.withValues(alpha: 0.28)) : null,
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
                  color: color,
                ),
          ),
          if (details != null && details!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              details!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF4B6B66),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
