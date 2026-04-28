import 'package:shared_preferences/shared_preferences.dart';

class SavedBleDevice {
  const SavedBleDevice({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

abstract class BleDeviceStore {
  Future<SavedBleDevice?> load();

  Future<void> save(SavedBleDevice device);

  Future<void> clear();
}

class SharedPreferencesBleDeviceStore implements BleDeviceStore {
  SharedPreferencesBleDeviceStore({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String _deviceIdKey = 'ble.last_device_id';
  static const String _deviceNameKey = 'ble.last_device_name';

  final Future<SharedPreferences> Function() _prefsLoader;

  @override
  Future<SavedBleDevice?> load() async {
    final prefs = await _prefsLoader();
    final id = prefs.getString(_deviceIdKey)?.trim() ?? '';
    if (id.isEmpty) {
      return null;
    }
    final name = prefs.getString(_deviceNameKey)?.trim() ?? '';
    return SavedBleDevice(id: id, name: name);
  }

  @override
  Future<void> save(SavedBleDevice device) async {
    final prefs = await _prefsLoader();
    await prefs.setString(_deviceIdKey, device.id);
    await prefs.setString(_deviceNameKey, device.name);
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefsLoader();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_deviceNameKey);
  }
}
