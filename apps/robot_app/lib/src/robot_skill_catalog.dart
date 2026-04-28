import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

const String kSkillActionsAsset =
    'assets/robot_skill/do_action/ext_actions.json';
const String kDogBehaviorsAsset =
    'assets/robot_skill/do_dog_behavior/dog_behaviors.json';

class RobotSkillCatalog {
  const RobotSkillCatalog({
    required this.actions,
    required this.behaviors,
    required this.duplicateActionIds,
  });

  final List<SkillActionItem> actions;
  final List<SkillBehaviorItem> behaviors;
  final Set<int> duplicateActionIds;

  static Future<RobotSkillCatalog> load({
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final actionText = await assetBundle.loadString(kSkillActionsAsset);
    final behaviorText = await assetBundle.loadString(kDogBehaviorsAsset);
    return parse(actionText: actionText, behaviorText: behaviorText);
  }

  static RobotSkillCatalog parse({
    required String actionText,
    required String behaviorText,
  }) {
    final actionJson = jsonDecode(actionText);
    final behaviorJson = jsonDecode(behaviorText);
    if (actionJson is! List || behaviorJson is! List) {
      throw const FormatException('robot_skill assets must be JSON arrays');
    }

    final seenActionIds = <int>{};
    final duplicateActionIds = <int>{};
    final actions = <SkillActionItem>[];
    for (final item in actionJson) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final actionId = item['action_id'];
      final actionName = item['action_name'];
      if (actionId is! int || actionName is! String) {
        continue;
      }
      if (!seenActionIds.add(actionId)) {
        duplicateActionIds.add(actionId);
      }
      actions.add(
        SkillActionItem(
          actionId: actionId,
          actionName: actionName,
        ),
      );
    }

    final behaviorByWireName = <String, DogBehavior>{
      for (final behavior in DogBehavior.values)
        dogBehaviorWireName(behavior): behavior,
    };
    final behaviors = <SkillBehaviorItem>[];
    for (final item in behaviorJson) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final behaviorName = item['behavior_name'];
      if (behaviorName is! String) {
        continue;
      }
      behaviors.add(
        SkillBehaviorItem(
          behaviorName: behaviorName,
          behavior: behaviorByWireName[behaviorName],
        ),
      );
    }

    return RobotSkillCatalog(
      actions: List<SkillActionItem>.unmodifiable(actions),
      behaviors: List<SkillBehaviorItem>.unmodifiable(behaviors),
      duplicateActionIds: Set<int>.unmodifiable(duplicateActionIds),
    );
  }
}

class SkillActionItem {
  const SkillActionItem({
    required this.actionId,
    required this.actionName,
  });

  final int actionId;
  final String actionName;

  String get stableKey => '$actionId:$actionName';
}

class SkillBehaviorItem {
  const SkillBehaviorItem({
    required this.behaviorName,
    required this.behavior,
  });

  final String behaviorName;
  final DogBehavior? behavior;

  bool get isSupported => behavior != null;
}

String dogBehaviorWireName(DogBehavior behavior) {
  final buffer = StringBuffer();
  final name = behavior.name;
  for (var index = 0; index < name.length; index += 1) {
    final char = name[index];
    final code = char.codeUnitAt(0);
    final isUpper = code >= 65 && code <= 90;
    final isDigit = code >= 48 && code <= 57;
    if (index > 0 && (isUpper || isDigit)) {
      buffer.write('_');
    }
    buffer.write(isUpper ? char.toLowerCase() : char);
  }
  return buffer.toString();
}
