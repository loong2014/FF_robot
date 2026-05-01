import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk_platform_interface.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockHandGestureSdkPlatform
    with MockPlatformInterfaceMixin
    implements HandGestureSdkPlatform {
  MockHandGestureSdkPlatform({Stream<HandGestureEvent>? eventsStream})
    : _events = eventsStream ?? const Stream<HandGestureEvent>.empty();

  final Stream<HandGestureEvent> _events;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<void> startRecognition() async {}

  @override
  Future<void> stopRecognition() async {}

  @override
  Future<void> updateRecognitionDebugInfo(Map<String, String> info) async {}

  @override
  Stream<HandGestureEvent> get events => _events;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final HandGestureSdkPlatform initialPlatform =
      HandGestureSdkPlatform.instance;

  test('$MethodChannelHandGestureSdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelHandGestureSdk>());
  });

  test('getPlatformVersion', () async {
    HandGestureSdkPlatform.instance = MockHandGestureSdkPlatform();
    final sdk = HandGestureSdk();

    expect(await sdk.getPlatformVersion(), '42');
  });

  test(
    'gestureEvents only emits gesture-typed events; poseEvents only pose; '
    'statusEvents excludes both',
    () async {
      final controller = StreamController<HandGestureEvent>();
      HandGestureSdkPlatform.instance = MockHandGestureSdkPlatform(
        eventsStream: controller.stream,
      );
      final sdk = HandGestureSdk();

      final gestures = <HandGestureEvent>[];
      final poses = <HandGestureEvent>[];
      final statuses = <HandGestureEvent>[];

      final gestureSub = sdk.gestureEvents.listen(gestures.add);
      final poseSub = sdk.poseEvents.listen(poses.add);
      final statusSub = sdk.statusEvents.listen(statuses.add);

      controller.add(
        const HandGestureEvent(
          type: 'gesture',
          message: '张开手掌',
          gesture: '张开手掌',
        ),
      );
      controller.add(
        const HandGestureEvent(type: 'pose', message: '站起', pose: '站起'),
      );
      controller.add(
        const HandGestureEvent(type: 'status', message: '相机已就绪'),
      );
      controller.add(
        const HandGestureEvent(type: 'closed', message: '识别页关闭'),
      );

      await Future<void>.delayed(Duration.zero);

      expect(gestures.map((e) => e.message), <String>['张开手掌']);
      expect(poses.map((e) => e.message), <String>['站起']);
      expect(statuses.map((e) => e.type), <String>['status', 'closed']);

      await gestureSub.cancel();
      await poseSub.cancel();
      await statusSub.cancel();
      await controller.close();
    },
  );

  test(
    'commands stream is driven only by gestureEvents and ignores pose noise',
    () async {
      final controller = StreamController<HandGestureEvent>();
      HandGestureSdkPlatform.instance = MockHandGestureSdkPlatform(
        eventsStream: controller.stream,
      );
      final sdk = HandGestureSdk();

      final commands = <HandGestureCommand>[];
      final sub = sdk.commands.listen(commands.add);

      // 单帧握拳 -> command 模式应直接产出 stop。
      controller.add(
        const HandGestureEvent(
          type: 'gesture',
          message: '握拳',
          gesture: '握拳',
          confidence: 0.95,
          metrics: <String, dynamic>{
            'handDetected': true,
            'handBBoxArea': 0.18,
            'handCenterX': 0.5,
            'handCenterY': 0.5,
          },
        ),
      );
      // 姿态事件不应该产出任何命令。
      controller.add(
        const HandGestureEvent(
          type: 'pose',
          message: '站起',
          pose: '站起',
          confidence: 0.8,
          metrics: <String, dynamic>{
            'leftKneeAngle': 170.0,
            'rightKneeAngle': 170.0,
          },
        ),
      );
      // 状态事件同理不应该产出命令。
      controller.add(
        const HandGestureEvent(type: 'status', message: '相机已就绪'),
      );

      await Future<void>.delayed(Duration.zero);

      expect(commands, hasLength(1));
      expect(commands.single.type, HandGestureCommandType.stop);
      expect(commands.single.message, '握拳停止移动');

      await sub.cancel();
      await controller.close();
    },
  );
}
