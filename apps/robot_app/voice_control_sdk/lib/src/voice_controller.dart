import 'voice_backend.dart';
import 'voice_models.dart';

class VoiceController {
  VoiceController([VoiceBackend? backend])
      : _backend = backend ?? SherpaVoiceBackend();

  final VoiceBackend _backend;

  Stream<VoiceEvent> get events => _backend.events;

  Stream<VoiceWakeEvent> get onWake =>
      events.where((event) => event is VoiceWakeEvent).cast<VoiceWakeEvent>();

  Stream<VoiceAsrEvent> get onAsr =>
      events.where((event) => event is VoiceAsrEvent).cast<VoiceAsrEvent>();

  Stream<VoiceCommandEvent> get onCommand => events
      .where((event) => event is VoiceCommandEvent)
      .cast<VoiceCommandEvent>();

  Stream<VoiceStateEvent> get state =>
      events.where((event) => event is VoiceStateEvent).cast<VoiceStateEvent>();

  Future<String?> getPlatformVersion() {
    return _backend.getPlatformVersion();
  }

  Future<bool> ensurePermissions() {
    return _backend.ensurePermissions();
  }

  Future<void> startListening({
    VoiceConfig config = const VoiceConfig(),
  }) {
    return _backend.start(config: config);
  }

  Future<void> stopListening() {
    return _backend.stop();
  }

  Future<void> dispose() {
    return _backend.dispose();
  }
}
