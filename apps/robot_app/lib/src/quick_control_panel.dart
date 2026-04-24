import 'package:flutter/material.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

class QuickControlPanel extends StatelessWidget {
  const QuickControlPanel({
    super.key,
    required this.client,
    required this.isConnected,
    this.onRequireConnection,
    this.onMessage,
  });

  final RobotClient client;
  final bool isConnected;
  final VoidCallback? onRequireConnection;
  final ValueChanged<String>? onMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '单点下发常用动作，适合联调时先验证最短控制链路。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF4B6B66),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '基础姿态',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF183936),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _QuickActionButton(
              icon: Icons.accessibility_new_rounded,
              label: '站立',
              accent: const Color(0xFF1F7A6F),
              onPressed: () => _invoke(
                commandLabel: 'stand',
                action: client.stand,
              ),
            ),
            _QuickActionButton(
              icon: Icons.airline_seat_recline_extra_rounded,
              label: '坐下',
              accent: const Color(0xFF2F5D58),
              onPressed: () => _invoke(
                commandLabel: 'sit',
                action: client.sit,
              ),
            ),
            _QuickActionButton(
              icon: Icons.stop_circle_outlined,
              label: '停止',
              accent: const Color(0xFFC05621),
              onPressed: () => _invoke(
                commandLabel: 'stop',
                action: client.stop,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '常用行为',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF183936),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _QuickActionButton(
              icon: Icons.waving_hand_rounded,
              label: '招手',
              accent: const Color(0xFF3A6EA5),
              onPressed: () => _invoke(
                commandLabel: 'wave_hand',
                action: () => client.doDogBehavior(DogBehavior.waveHand),
              ),
            ),
            _QuickActionButton(
              icon: Icons.front_hand_rounded,
              label: '握手',
              accent: const Color(0xFF6B7280),
              onPressed: () => _invoke(
                commandLabel: 'shake_hand',
                action: () => client.doDogBehavior(DogBehavior.shakeHand),
              ),
            ),
            _QuickActionButton(
              icon: Icons.self_improvement_rounded,
              label: '鞠躬',
              accent: const Color(0xFF8B5E34),
              onPressed: () => _invoke(
                commandLabel: 'bow',
                action: () => client.doDogBehavior(DogBehavior.bow),
              ),
            ),
            _QuickActionButton(
              icon: Icons.music_note_rounded,
              label: '跳舞',
              accent: const Color(0xFF7B5EA7),
              onPressed: () => _invoke(
                commandLabel: 'dance_in_place',
                action: () => client.doDogBehavior(DogBehavior.danceInPlace),
              ),
            ),
            _QuickActionButton(
              icon: Icons.hotel_rounded,
              label: '休息',
              accent: const Color(0xFF4C8C7A),
              onPressed: () => _invoke(
                commandLabel: 'rest',
                action: () => client.doDogBehavior(DogBehavior.rest),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _invoke({
    required String commandLabel,
    required Future<void> Function() action,
  }) async {
    if (!isConnected) {
      final callback = onRequireConnection;
      if (callback != null) {
        callback();
      } else {
        onMessage?.call('请先连接机器人再发送动作');
      }
      return;
    }

    try {
      await action();
      onMessage?.call('已发送 $commandLabel');
    } catch (error) {
      onMessage?.call('发送 $commandLabel 失败: $error');
    }
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: accent.withValues(alpha: 0.14),
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: accent.withValues(alpha: 0.2)),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
