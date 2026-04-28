import Flutter
import AVFoundation

final class VoiceListeningCoordinator: NSObject {
  private let queue = DispatchQueue(label: "com.xinzhang.voice_control_sdk.audio")

  private let audioEngine = AVAudioEngine()
  private var isListening = false
  private var config = VoiceConfig()

  func start(config: VoiceConfig) {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.config = config
      self.isListening = true
      self.requestPermissionsAndStart()
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.stopInternal(reason: "stopped by user")
    }
  }

  private func requestPermissionsAndStart() {
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      guard let self = self else { return }
      guard granted else {
        VoiceControlSdkPlugin.publishEvent(
          [
            "type": "error",
            "code": "microphone_permission_denied",
            "message": "Microphone permission is not authorized",
            "source": "ios",
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
          ]
        )
        self.queue.async {
          self.stopInternal(reason: "microphone_permission_denied")
        }
        return
      }

      self.queue.async {
        guard self.startAudioSessionIfNeeded() else { return }
        self.startCapture()
      }
    }
  }

  private func startAudioSessionIfNeeded() -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers, .allowBluetooth])
      try session.setPreferredSampleRate(Double(config.sampleRate))
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "error",
          "code": "audio_session_error",
          "message": error.localizedDescription,
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      queue.async {
        self.stopInternal(reason: "audio_session_error")
      }
      return false
    }

    return true
  }

  private func startCapture() {
    guard isListening else { return }

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    let sampleRate = Int(inputFormat.sampleRate)

    if audioEngine.isRunning {
      return
    }

    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.emitBuffer(buffer, sampleRate: sampleRate)
    }

    do {
      try audioEngine.start()
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "state",
          "state": "listening",
          "message": "正在采集音频",
          "listening": true,
          "activeListening": false,
          "engine": "sherpa",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "telemetry",
          "message": "iOS microphone capture started",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
    } catch {
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "error",
          "code": "audio_engine_start_failed",
          "message": error.localizedDescription,
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      queue.async {
        self.stopInternal(reason: "audio_engine_start_failed")
      }
    }
  }

  private func emitBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Int) {
    guard isListening else { return }
    guard let channelData = buffer.floatChannelData else {
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "error",
          "code": "audio_stream_error",
          "message": "AVAudioPCMBuffer does not contain float channel data",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      return
    }

    let frameCount = Int(buffer.frameLength)
    let channel = channelData[0]
    let samples = Array(UnsafeBufferPointer(start: channel, count: frameCount))
    let data = samples.withUnsafeBufferPointer { pointer in
      Data(buffer: pointer)
    }

    VoiceControlSdkPlugin.publishEvent(
      [
        "type": "audio",
        "format": "f32le",
        "samples": FlutterStandardTypedData(bytes: data),
        "sampleRate": sampleRate,
        "channels": 1,
        "sampleCount": frameCount,
        "source": "ios",
        "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
      ]
    )
  }

  private func stopInternal(reason: String) {
    isListening = false
    if audioEngine.isRunning {
      audioEngine.inputNode.removeTap(onBus: 0)
      audioEngine.stop()
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    VoiceControlSdkPlugin.publishEvent(
      [
        "type": "state",
        "state": "stopped",
        "message": reason,
        "listening": false,
        "activeListening": false,
        "engine": "sherpa",
        "source": "ios",
        "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
      ]
    )
  }
}

struct VoiceConfig {
  let sampleRate: Int
  let wakeWord: String
  let sensitivity: Double

  init(
    sampleRate: Int = 16000,
    wakeWord: String = "D-Dog",
    sensitivity: Double = 0.65
  ) {
    self.sampleRate = sampleRate
    self.wakeWord = wakeWord
    self.sensitivity = sensitivity
  }

  init(arguments: [String: Any]?) {
    let arguments = arguments ?? [:]
    self.init(
      sampleRate: (arguments["sampleRate"] as? NSNumber)?.intValue ?? 16000,
      wakeWord: (arguments["wakeWord"] as? String) ?? "D-Dog",
      sensitivity: (arguments["sensitivity"] as? NSNumber)?.doubleValue ?? 0.65
    )
  }
}
