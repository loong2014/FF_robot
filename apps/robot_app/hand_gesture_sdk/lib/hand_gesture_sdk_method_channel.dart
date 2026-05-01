import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'hand_gesture_sdk_event.dart';
import 'hand_gesture_sdk_platform_interface.dart';

/// An implementation of [HandGestureSdkPlatform] that uses method channels.
class MethodChannelHandGestureSdk extends HandGestureSdkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('hand_gesture_sdk');
  @visibleForTesting
  final eventChannel = const EventChannel('hand_gesture_sdk/events');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<void> startRecognition() {
    return methodChannel.invokeMethod<void>('startRecognition');
  }

  @override
  Future<void> stopRecognition() {
    return methodChannel.invokeMethod<void>('stopRecognition');
  }

  @override
  Future<void> updateRecognitionDebugInfo(Map<String, String> info) {
    return methodChannel.invokeMethod<void>('updateRecognitionDebugInfo', info);
  }

  @override
  Stream<HandGestureEvent> get events {
    return eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return HandGestureEvent.fromMap(event);
      }
      return HandGestureEvent(type: 'status', message: event?.toString() ?? '');
    });
  }
}
