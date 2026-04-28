import 'package:flutter_test/flutter_test.dart';
import 'package:robot_app/src/ble_device_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SharedPreferencesBleDeviceStore saves, loads, and clears device',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SharedPreferencesBleDeviceStore();

    expect(await store.load(), isNull);

    await store.save(const SavedBleDevice(id: 'robot-1', name: 'RobotDog-1'));

    final savedDevice = await store.load();
    expect(savedDevice?.id, 'robot-1');
    expect(savedDevice?.name, 'RobotDog-1');

    await store.clear();

    expect(await store.load(), isNull);
  });
}
