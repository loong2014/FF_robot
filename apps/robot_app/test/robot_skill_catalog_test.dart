import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/robot_skill_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads robot_skill assets and maps supported behaviors', () async {
    final catalog = await RobotSkillCatalog.load();

    expect(catalog.actions, hasLength(140));
    expect(catalog.behaviors, hasLength(39));
    expect(catalog.duplicateActionIds, contains(20589));
    expect(
      catalog.behaviors.where((item) => !item.isSupported),
      isEmpty,
    );
  });

  test('converts DogBehavior enum names to wire behavior names', () {
    expect(dogBehaviorWireName(DogBehavior.waveHand), 'wave_hand');
    expect(dogBehaviorWireName(DogBehavior.cute2), 'cute_2');
    expect(
      dogBehaviorWireName(DogBehavior.recoveryBalanceStand1),
      'recovery_balance_stand_1',
    );
  });
}
