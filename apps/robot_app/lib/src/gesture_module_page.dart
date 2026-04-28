import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk.dart';

class GestureModulePage extends StatefulWidget {
  const GestureModulePage({super.key});

  @override
  State<GestureModulePage> createState() => _GestureModulePageState();
}

class _GestureModulePageState extends State<GestureModulePage> {
  final HandGestureSdk _sdk = HandGestureSdk.instance;
  StreamSubscription<HandGestureEvent>? _subscription;
  StreamSubscription<HandGestureCommand>? _commandSubscription;
  final List<HandGestureEvent> _events = <HandGestureEvent>[];
  final List<HandGestureCommand> _commands = <HandGestureCommand>[];
  String _latestGesture = '暂无';
  String _latestCommand = '暂无';
  String _status = '尚未启动';

  @override
  void initState() {
    super.initState();
    _subscription = _sdk.events.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _events.insert(0, event);
        _status = event.message;
        if (event.gesture != null && event.gesture!.isNotEmpty) {
          _latestGesture = event.gesture!;
        }
      });
    });
    _commandSubscription = _sdk.commands.listen((command) {
      if (!mounted) {
        return;
      }
      setState(() {
        _commands.insert(0, command);
        _latestCommand = command.message;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _commandSubscription?.cancel();
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
  }

  Future<void> _closeRecognition() async {
    if (!_isSupportedPlatform) {
      return;
    }
    await _sdk.stopRecognition();
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
                title: '最新手势',
                value: _latestGesture,
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '最新命令',
                value: _latestCommand,
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
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _events.length + _commands.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      if (index < _events.length) {
                        final event = _events[index];
                        return Text(
                          '[${event.type}] ${event.message}${event.gesture == null ? '' : ' | ${event.gesture}'}${event.pose == null ? '' : ' | ${event.pose}'}',
                        );
                      }
                      final command = _commands[index - _events.length];
                      return Text(
                        '[command:${command.type.name}] ${command.message}${command.gesture == null ? '' : ' | ${command.gesture}'}${command.pose == null ? '' : ' | ${command.pose}'}',
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
