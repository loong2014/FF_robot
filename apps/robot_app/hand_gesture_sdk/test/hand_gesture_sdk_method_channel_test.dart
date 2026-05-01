import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelHandGestureSdk platform = MethodChannelHandGestureSdk();
  const MethodChannel channel = MethodChannel('hand_gesture_sdk');
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          calls.add(methodCall);
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('updateRecognitionDebugInfo sends debug info to native page', () async {
    await platform.updateRecognitionDebugInfo(<String, String>{
      'mode': 'follow',
      'connection': 'ble/connected',
    });

    expect(calls.single.method, 'updateRecognitionDebugInfo');
    expect(calls.single.arguments, <String, String>{
      'mode': 'follow',
      'connection': 'ble/connected',
    });
  });
}
