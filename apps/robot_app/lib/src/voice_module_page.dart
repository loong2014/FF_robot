import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

class VoiceModulePage extends StatefulWidget {
  const VoiceModulePage({super.key});

  @override
  State<VoiceModulePage> createState() => _VoiceModulePageState();
}

class _VoiceModulePageState extends State<VoiceModulePage> {
  final VoiceController _voiceController = VoiceController();
  final TextEditingController _wakeWordController =
      TextEditingController(text: 'Lumi');

  StreamSubscription<VoiceEvent>? _eventSubscription;

  final List<VoiceEvent> _events = <VoiceEvent>[];
  VoiceStateEvent? _latestState;
  VoiceWakeEvent? _latestWake;
  VoiceAsrEvent? _latestAsr;
  VoiceErrorEvent? _latestError;
  bool _listening = false;
  bool _retainLatestError = false;
  double _sensitivity = 0.82;
  Duration _wakeDebounce = const Duration(milliseconds: 1200);
  VoiceLanguage _modelLanguage = VoiceLanguage.mixed;
  String _statusMessage = '尚未启动';

  @override
  void initState() {
    super.initState();
    _eventSubscription = _voiceController.events.listen(_handleEvent);
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    _wakeWordController.dispose();
    unawaited(_voiceController.dispose());
    super.dispose();
  }

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _startListening() async {
    if (!_isSupportedPlatform) {
      setState(() {
        _statusMessage = '当前仅支持 Android / iOS';
      });
      return;
    }

    final bool hasPermissions = await _voiceController.ensurePermissions();
    if (!hasPermissions) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '请先允许麦克风权限；Android 13+ 还需要允许通知权限';
        _listening = false;
      });
      return;
    }

    final config = VoiceConfig(
      wakeWord: _wakeWordController.text.trim().isEmpty
          ? 'Lumi'
          : _wakeWordController.text.trim(),
      sensitivity: _sensitivity,
      wakeDebounce: _wakeDebounce,
      modelLanguage: _modelLanguage,
    );

    try {
      await _voiceController.startListening(config: config);
      if (!mounted) {
        return;
      }
      setState(() {
        _listening = true;
        _latestError = null;
        _retainLatestError = false;
        _statusMessage = '正在等待 ${config.wakeWord}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = '启动失败: $error';
        _listening = false;
      });
    }
  }

  Future<void> _stopListening() async {
    await _voiceController.stopListening();
    if (!mounted) {
      return;
    }
    setState(() {
      _listening = false;
      _retainLatestError = false;
      _statusMessage = '已停止监听';
    });
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _restartListening() async {
    if (_listening) {
      await _stopListening();
    }
    await _startListening();
  }

  void _handleEvent(VoiceEvent event) {
    if (!mounted) {
      return;
    }

    bool shouldStop = false;
    setState(() {
      _events.insert(0, event);
      if (_events.length > 80) {
        _events.removeLast();
      }
      if (event is VoiceStateEvent) {
        _latestState = event;
        _listening = event.listening;
        if (!_retainLatestError && event.state != VoiceRecognitionState.error) {
          _latestError = null;
        }
        if (event.state == VoiceRecognitionState.listening ||
            event.state == VoiceRecognitionState.wakeDetected) {
          _retainLatestError = false;
        }
        _statusMessage =
            event.message.isNotEmpty ? event.message : event.state.wireName;
      } else if (event is VoiceWakeEvent) {
        _latestWake = event;
        _statusMessage = '唤醒词: ${event.wakeWord}';
      } else if (event is VoiceAsrEvent) {
        _latestAsr = event;
        _statusMessage =
            event.isFinal ? '识别完成: ${event.text}' : '识别中: ${event.text}';
      } else if (event is VoiceErrorEvent) {
        _latestError = event;
        _statusMessage = event.recoveryHint;
        if (event.requiresManualRecovery) {
          _retainLatestError = true;
          _listening = false;
          shouldStop = true;
        }
      }
    });

    if (shouldStop) {
      unawaited(_voiceController.stopListening());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2E8),
      appBar: AppBar(
        title: const Text('语音控制模块'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '先手动启动监听，再说唤醒词 "Lumi"。当前版本使用 Sherpa 的 KWS + ASR + VAD 双阶段链路：先唤醒，再持续识别到静音结束。Android 侧使用前台监听，iOS 仅前台可用。',
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
                          onPressed:
                              _isSupportedPlatform ? _toggleListening : null,
                          icon: Icon(
                            _listening
                                ? Icons.stop_circle_outlined
                                : Icons.mic_rounded,
                            size: 18,
                          ),
                          label: Text(_listening ? '停止监听' : '开始监听'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _isSupportedPlatform ? _restartListening : null,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('应用并重启'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _listening ? _stopListening : null,
                          icon: const Icon(Icons.power_settings_new_rounded,
                              size: 18),
                          label: const Text('立即停止'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _StatusCard(
                      title: '当前状态',
                      value: _buildStateHeadline(),
                      details: _buildStateDetails(),
                    ),
                    const SizedBox(height: 12),
                    if (_latestError != null)
                      _RecoveryCard(
                        error: _latestError!,
                        onRetry:
                            _isSupportedPlatform ? _restartListening : null,
                      ),
                    if (_latestError != null) const SizedBox(height: 12),
                    _SettingsCard(
                      wakeWordController: _wakeWordController,
                      sensitivity: _sensitivity,
                      onSensitivityChanged: (value) {
                        setState(() {
                          _sensitivity = value;
                        });
                      },
                      modelLanguage: _modelLanguage,
                      onModelLanguageChanged: (value) {
                        setState(() {
                          _modelLanguage = value;
                        });
                      },
                      wakeDebounce: _wakeDebounce,
                      onWakeDebounceChanged: (value) {
                        setState(() {
                          _wakeDebounce = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _StatusCard(
                      title: '最新唤醒',
                      value: _latestWake == null
                          ? '暂无'
                          : '${_latestWake!.recognizedText} / ${_latestWake!.confidence.toStringAsFixed(2)}',
                      details: _latestWake == null
                          ? null
                          : '唤醒词 ${_latestWake!.wakeWord} · ${_latestWake!.language.wireName}',
                    ),
                    const SizedBox(height: 12),
                    _StatusCard(
                      title: '模型语言',
                      value: _describeLanguage(_modelLanguage),
                      details: 'KWS 会按模型语言自动收敛，ASR 默认保持中英双语',
                    ),
                    const SizedBox(height: 12),
                    _StatusCard(
                      title: '最新识别',
                      value: _latestAsr == null
                          ? '暂无'
                          : (_latestAsr!.isFinal ? '最终结果' : '实时转写'),
                      details: _latestAsr == null
                          ? null
                          : '${_latestAsr!.text} · ${_latestAsr!.language.wireName}',
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
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _events.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          if (event is VoiceWakeEvent) {
                            return Text(
                              '[wake] ${event.recognizedText} (${event.language.wireName}) / ${event.confidence.toStringAsFixed(2)}',
                            );
                          }
                          if (event is VoiceAsrEvent) {
                            return Text(
                              '[asr] ${event.isFinal ? "final" : "partial"} | ${event.text}',
                            );
                          }
                          if (event is VoiceStateEvent) {
                            return Text(
                              '[state] ${event.state.wireName} | ${event.message}',
                            );
                          }
                          if (event is VoiceErrorEvent) {
                            return Text(
                              '[error] ${event.code} | ${event.message}',
                              style: const TextStyle(color: Color(0xFFB42318)),
                            );
                          }
                          if (event is VoiceTelemetryEvent) {
                            return Text(
                              '[telemetry] ${event.message}',
                            );
                          }
                          return Text(
                            '[telemetry] ${event.type} | ${event.timestamp.toIso8601String()}',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _buildStateHeadline() {
    if (_latestError != null) {
      return '需要恢复';
    }
    if (_statusMessage.isNotEmpty) {
      return _statusMessage;
    }
    if (_latestState != null) {
      return _describeVoiceState(_latestState!.state);
    }
    return '尚未启动';
  }

  String _describeVoiceState(VoiceRecognitionState state) {
    switch (state) {
      case VoiceRecognitionState.stopped:
        return '已停止';
      case VoiceRecognitionState.starting:
        return '正在启动';
      case VoiceRecognitionState.listening:
        return '监听中';
      case VoiceRecognitionState.wakeDetected:
        return '已唤醒';
      case VoiceRecognitionState.activeListening:
        return '唤醒处理中';
      case VoiceRecognitionState.cooldown:
        return '短暂恢复中';
      case VoiceRecognitionState.error:
        return '异常';
    }
  }

  String _describeLanguage(VoiceLanguage language) {
    switch (language) {
      case VoiceLanguage.zh:
        return '中文模型';
      case VoiceLanguage.en:
        return '英文模型';
      case VoiceLanguage.mixed:
        return '中英混合模型';
      case VoiceLanguage.unknown:
        return '未指定模型';
    }
  }

  String? _buildStateDetails() {
    final parts = <String>[];
    if (_latestState != null) {
      parts.add('引擎 ${_latestState!.engine.wireName}');
    }
    if (_latestError != null) {
      parts.add(_latestError!.recoveryHint);
    } else if (!_listening) {
      parts.add('当前未监听，点“开始监听”即可进入待唤醒状态');
    } else {
      parts.add('正在等待唤醒词 Lumi');
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' · ');
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    this.details,
  });

  final String title;
  final String value;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
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
          if (details != null) ...<Widget>[
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

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.error,
    required this.onRetry,
  });

  final VoiceErrorEvent error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = error.requiresManualRecovery
        ? const Color(0xFFE06B36)
        : const Color(0xFFB42318);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: borderColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '恢复建议',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF183936),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            error.message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF7A271A),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            error.recoveryHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF4B6B66),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('重新启动监听'),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('检查权限'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.wakeWordController,
    required this.sensitivity,
    required this.onSensitivityChanged,
    required this.modelLanguage,
    required this.onModelLanguageChanged,
    required this.wakeDebounce,
    required this.onWakeDebounceChanged,
  });

  final TextEditingController wakeWordController;
  final double sensitivity;
  final ValueChanged<double> onSensitivityChanged;
  final VoiceLanguage modelLanguage;
  final ValueChanged<VoiceLanguage> onModelLanguageChanged;
  final Duration wakeDebounce;
  final ValueChanged<Duration> onWakeDebounceChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '唤醒配置',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF4B6B66),
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: wakeWordController,
            decoration: const InputDecoration(
              labelText: '唤醒词',
              hintText: 'Lumi',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<VoiceLanguage>(
            initialValue: modelLanguage,
            items: const <DropdownMenuItem<VoiceLanguage>>[
              DropdownMenuItem<VoiceLanguage>(
                value: VoiceLanguage.en,
                child: Text('英文模型'),
              ),
              DropdownMenuItem<VoiceLanguage>(
                value: VoiceLanguage.zh,
                child: Text('中文模型'),
              ),
              DropdownMenuItem<VoiceLanguage>(
                value: VoiceLanguage.mixed,
                child: Text('中英混合模型'),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              onModelLanguageChanged(value);
            },
            decoration: const InputDecoration(
              labelText: '模型语言',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '唤醒灵敏度：${sensitivity.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Slider(
            min: 0.3,
            max: 0.95,
            divisions: 13,
            value: sensitivity.clamp(0.3, 0.95),
            onChanged: onSensitivityChanged,
          ),
          const SizedBox(height: 8),
          Text(
            '唤醒冷却：${wakeDebounce.inMilliseconds} ms',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Slider(
            min: 500,
            max: 2500,
            divisions: 8,
            value: wakeDebounce.inMilliseconds.toDouble().clamp(500, 2500),
            onChanged: (value) {
              onWakeDebounceChanged(
                Duration(milliseconds: value.round()),
              );
            },
          ),
        ],
      ),
    );
  }
}
