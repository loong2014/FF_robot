import 'package:flutter/material.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

enum ControlActionKind { stand, sit, stop, dogBehavior, actionId }

class ControlAction {
  const ControlAction({
    required this.label,
    required this.icon,
    required this.kind,
    this.behavior,
    this.actionId,
  });

  final String label;
  final IconData icon;
  final ControlActionKind kind;
  final DogBehavior? behavior;
  final int? actionId;
}

const List<ControlAction> kControlActions = <ControlAction>[
  ControlAction(
    label: '站立',
    icon: Icons.pets,
    kind: ControlActionKind.stand,
  ),
  ControlAction(
    label: '趴下',
    icon: Icons.airline_seat_flat_rounded,
    kind: ControlActionKind.actionId,
    actionId: 2,
  ),
  ControlAction(
    label: '坐下',
    icon: Icons.event_seat_rounded,
    kind: ControlActionKind.sit,
  ),
  ControlAction(
    label: '鞠躬',
    icon: Icons.accessibility_new_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.bow,
  ),
  ControlAction(
    label: '摇尾巴',
    icon: Icons.waving_hand_rounded,
    kind: ControlActionKind.actionId,
    actionId: 20483,
  ),
  ControlAction(
    label: '撒娇',
    icon: Icons.favorite_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.expressAffection,
  ),
  ControlAction(
    label: '伸懒腰',
    icon: Icons.self_improvement_rounded,
    kind: ControlActionKind.actionId,
    actionId: 20503,
  ),
  ControlAction(
    label: '心急',
    icon: Icons.speed_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.eager,
  ),
  ControlAction(
    label: '转圈',
    icon: Icons.rotate_right_rounded,
    kind: ControlActionKind.actionId,
    actionId: 20482,
  ),
  ControlAction(
    label: '抖一抖',
    icon: Icons.vibration_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.shakeSelf,
  ),
  ControlAction(
    label: '跳舞',
    icon: Icons.music_note_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.danceInPlace,
  ),
  ControlAction(
    label: '握手',
    icon: Icons.front_hand_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.shakeHand,
  ),
  ControlAction(
    label: '挥手',
    icon: Icons.back_hand_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.waveHand,
  ),
  ControlAction(
    label: '比心',
    icon: Icons.favorite_border_rounded,
    kind: ControlActionKind.actionId,
    actionId: 20593,
  ),
  ControlAction(
    label: '俯卧撑',
    icon: Icons.fitness_center_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.pushUp,
  ),
  ControlAction(
    label: '匍匐',
    icon: Icons.explore_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.crawl,
  ),
  ControlAction(
    label: '左空翻',
    icon: Icons.flip_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.leftFlip,
  ),
  ControlAction(
    label: '右空翻',
    icon: Icons.flip_rounded,
    kind: ControlActionKind.dogBehavior,
    behavior: DogBehavior.rightFlip,
  ),
];
