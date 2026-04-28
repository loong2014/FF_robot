import 'package:flutter/services.dart';

import 'voice_models.dart';
import 'voice_control_sdk_platform_interface.dart';

class MethodChannelVoiceControlSdk extends VoiceControlSdkPlatform {
  MethodChannelVoiceControlSdk({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('voice_control_sdk'),
        _eventChannel =
            eventChannel ?? const EventChannel('voice_control_sdk/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<Map<String, Object?>>? _events;

  @override
  Future<String?> getPlatformVersion() {
    return _methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<void> startListening({
    VoiceConfig config = const VoiceConfig(),
  }) {
    return _methodChannel.invokeMethod<void>(
      'startListening',
      config.toMap(),
    );
  }

  @override
  Future<void> stopListening() {
    return _methodChannel.invokeMethod<void>('stopListening');
  }

  @override
  Stream<Map<String, Object?>> get events {
    _events ??= _eventChannel.receiveBroadcastStream().map(_mapEvent);
    return _events!;
  }

  Map<String, Object?> _mapEvent(dynamic event) {
    if (event is Map) {
      final result = <String, Object?>{};
      for (final entry in event.entries) {
        result[entry.key.toString()] = entry.value;
      }
      return result;
    }
    return <String, Object?>{
      'type': 'telemetry',
      'message': event?.toString() ?? '',
      'timestampMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    };
  }
}
