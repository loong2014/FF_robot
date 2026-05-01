import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'hand_gesture_sdk_method_channel.dart';
import 'hand_gesture_sdk_event.dart';

abstract class HandGestureSdkPlatform extends PlatformInterface {
  /// Constructs a HandGestureSdkPlatform.
  HandGestureSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static HandGestureSdkPlatform _instance = MethodChannelHandGestureSdk();

  /// The default instance of [HandGestureSdkPlatform] to use.
  ///
  /// Defaults to [MethodChannelHandGestureSdk].
  static HandGestureSdkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [HandGestureSdkPlatform] when
  /// they register themselves.
  static set instance(HandGestureSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> startRecognition() {
    throw UnimplementedError('startRecognition() has not been implemented.');
  }

  Future<void> stopRecognition() {
    throw UnimplementedError('stopRecognition() has not been implemented.');
  }

  Future<void> updateRecognitionDebugInfo(Map<String, String> info) {
    throw UnimplementedError(
      'updateRecognitionDebugInfo() has not been implemented.',
    );
  }

  Stream<HandGestureEvent> get events {
    throw UnimplementedError('events has not been implemented.');
  }
}
