import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'voice_models.dart';
import 'voice_control_sdk_method_channel.dart';

abstract class VoiceControlSdkPlatform extends PlatformInterface {
  VoiceControlSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static VoiceControlSdkPlatform _instance = MethodChannelVoiceControlSdk();

  static VoiceControlSdkPlatform get instance => _instance;

  static set instance(VoiceControlSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  Future<bool> ensurePermissions() {
    throw UnimplementedError('ensurePermissions() has not been implemented.');
  }

  Future<void> startListening({
    VoiceConfig config = const VoiceConfig(),
  }) {
    throw UnimplementedError('startListening() has not been implemented.');
  }

  Future<void> stopListening() {
    throw UnimplementedError('stopListening() has not been implemented.');
  }

  Stream<Map<String, Object?>> get events {
    throw UnimplementedError('events has not been implemented.');
  }
}
