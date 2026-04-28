import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk_platform_interface.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk_method_channel.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk_event.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockHandGestureSdkPlatform
    with MockPlatformInterfaceMixin
    implements HandGestureSdkPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<void> startRecognition() async {}

  @override
  Future<void> stopRecognition() async {}

  @override
  Stream<HandGestureEvent> get events => const Stream<HandGestureEvent>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final HandGestureSdkPlatform initialPlatform =
      HandGestureSdkPlatform.instance;

  test('$MethodChannelHandGestureSdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelHandGestureSdk>());
  });

  test('getPlatformVersion', () async {
    MockHandGestureSdkPlatform fakePlatform = MockHandGestureSdkPlatform();
    HandGestureSdkPlatform.instance = fakePlatform;
    HandGestureSdk handGestureSdkPlugin = HandGestureSdk();

    expect(await handGestureSdkPlugin.getPlatformVersion(), '42');
  });
}
