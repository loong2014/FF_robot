import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

class FakeVoiceBackend implements VoiceBackend {
  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  VoiceConfig? lastConfig;
  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<String?> getPlatformVersion() async => 'test-sherpa';

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<void> start({VoiceConfig config = const VoiceConfig()}) async {
    started = true;
    lastConfig = config;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }

  void emit(VoiceEvent event) {
    _events.add(event);
  }
}

void main() {
  test('VoiceController forwards Sherpa events and lifecycle calls', () async {
    final backend = FakeVoiceBackend();
    final controller = VoiceController(backend);

    final wakeEvents = <VoiceWakeEvent>[];
    final asrEvents = <VoiceAsrEvent>[];
    final commandEvents = <VoiceCommandEvent>[];
    final stateEvents = <VoiceStateEvent>[];
    final errorEvents = <VoiceErrorEvent>[];

    final wakeSub = controller.onWake.listen(wakeEvents.add);
    final asrSub = controller.onAsr.listen(asrEvents.add);
    final commandSub = controller.onCommand.listen(commandEvents.add);
    final stateSub = controller.state.listen(stateEvents.add);
    final errorSub = controller.events
        .where((event) => event is VoiceErrorEvent)
        .cast<VoiceErrorEvent>()
        .listen(errorEvents.add);
    addTearDown(wakeSub.cancel);
    addTearDown(asrSub.cancel);
    addTearDown(commandSub.cancel);
    addTearDown(stateSub.cancel);
    addTearDown(errorSub.cancel);

    await controller.startListening(
      config: const VoiceConfig(
        wakeWord: 'Lumi',
        sensitivity: 0.7,
        modelLanguage: VoiceLanguage.mixed,
      ),
    );

    expect(backend.started, isTrue);
    expect(backend.lastConfig?.wakeWord, 'Lumi');
    expect(backend.lastConfig?.engine, VoiceEngineType.sherpa);

    backend.emit(
      VoiceStateEvent(
        timestamp: DateTime.utc(2024),
        source: VoiceEventSource.android,
        payload: const <String, Object?>{'type': 'state'},
        state: VoiceRecognitionState.listening,
        message: 'ready',
        engine: VoiceEngineType.sherpa,
        listening: true,
        activeListening: false,
      ),
    );
    backend.emit(
      VoiceAsrEvent(
        timestamp: DateTime.utc(2024, 1, 1, 0, 0, 1),
        source: VoiceEventSource.android,
        payload: const <String, Object?>{'type': 'asr'},
        text: '站起来',
        language: VoiceLanguage.zh,
        confidence: 0.91,
        isFinal: true,
      ),
    );
    backend.emit(
      VoiceWakeEvent(
        timestamp: DateTime.utc(2024, 1, 1, 0, 0, 1),
        source: VoiceEventSource.android,
        payload: const <String, Object?>{'type': 'wake'},
        wakeWord: 'Lumi',
        recognizedText: '露米',
        resultLabel: 'lumi__zh_lu4',
        language: VoiceLanguage.zh,
        confidence: 0.93,
      ),
    );
    backend.emit(
      VoiceCommandEvent(
        timestamp: DateTime.utc(2024, 1, 1, 0, 0, 2),
        source: VoiceEventSource.android,
        payload: const <String, Object?>{'type': 'command'},
        command: VoiceCommand.sitDown,
        language: VoiceLanguage.zh,
        rawText: '坐下',
        normalizedText: '坐下',
        confidence: 0.88,
      ),
    );
    backend.emit(
      VoiceErrorEvent(
        timestamp: DateTime.utc(2024, 1, 1, 0, 0, 3),
        source: VoiceEventSource.android,
        payload: const <String, Object?>{'type': 'error'},
        code: 'sherpa_asset_missing',
        message: 'missing model',
      ),
    );

    await pumpEventQueue(times: 3);

    expect(stateEvents, hasLength(1));
    expect(stateEvents.single.state, VoiceRecognitionState.listening);
    expect(asrEvents, hasLength(1));
    expect(asrEvents.single.text, '站起来');
    expect(wakeEvents, hasLength(1));
    expect(wakeEvents.single.wakeWord, 'Lumi');
    expect(commandEvents, hasLength(1));
    expect(commandEvents.single.command, VoiceCommand.sitDown);
    expect(errorEvents, hasLength(1));
    expect(errorEvents.single.code, 'sherpa_asset_missing');
    expect(errorEvents.single.requiresManualRecovery, isTrue);
    expect(errorEvents.single.recoveryHint, isNotEmpty);

    expect(await controller.getPlatformVersion(), 'test-sherpa');

    await controller.stopListening();
    expect(backend.stopped, isTrue);

    await controller.dispose();
    expect(backend.disposed, isTrue);
  });
}
