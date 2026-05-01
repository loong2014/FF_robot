import Flutter
import AVFoundation
import UIKit

final class VoiceListeningCoordinator: NSObject {
  private let queue = DispatchQueue(label: "com.xinzhang.voice_control_sdk.audio")

  /// 媒体服务重置后旧 `AVAudioEngine` 会失效，继续访问 `inputNode` 会触发
  /// `required condition is false: inputNode != nullptr || outputNode != nullptr`。
  /// 每次完整 teardown 或丢弃引擎时替换为新实例。
  private var audioEngine = AVAudioEngine()
  private var converter: AVAudioConverter?
  private var hardwareFormat: AVAudioFormat?
  private var targetFormat: AVAudioFormat?
  private var notificationsRegistered = false
  /// 仅在成功 `installTap` 之后为 true，避免对从未挂 tap 的图调用 `removeTap`。
  private var tapInstalled = false

  private var isListening = false
  private var config = VoiceConfig()

  /// 在触摸 `AVAudioEngine` 的 `inputNode` / `prepare` 之前尽量确认有可用的录音路径，降低断言崩溃概率。
  private func hasUsableAudioInput(session: AVAudioSession) -> Bool {
    if #available(iOS 17.0, *) {
      if !session.currentRoute.inputs.isEmpty { return true }
      if let ports = session.availableInputs, !ports.isEmpty { return true }
      return false
    }
    return session.isInputAvailable
  }

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
      var options: AVAudioSession.CategoryOptions = [.duckOthers]
      if #available(iOS 17.0, *) {
        options.insert(.allowBluetoothHFP)
      } else {
        options.insert(.allowBluetooth)
      }
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
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
    registerSessionNotificationsIfNeeded()
    return true
  }

  private func startCapture() {
    guard isListening else { return }

    if audioEngine.isRunning {
      return
    }

    let session = AVAudioSession.sharedInstance()
    guard hasUsableAudioInput(session: session) else {
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "error",
          "code": "audio_engine_start_failed",
          "message": "No usable audio input route (routed=\(session.currentRoute.inputs.map { $0.portName }), available=\(session.availableInputs?.map { $0.portName } ?? []))",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      stopInternal(reason: "audio_input_unavailable")
      return
    }

    audioEngine.prepare()

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "error",
          "code": "audio_engine_start_failed",
          "message": "AVAudioEngine input format is invalid: rate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount)",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      stopInternal(reason: "audio_engine_input_invalid")
      return
    }

    let targetSampleRate = Double(config.sampleRate)
    guard let target = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: targetSampleRate,
      channels: 1,
      interleaved: false
    ) else {
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "error",
          "code": "audio_engine_start_failed",
          "message": "Failed to build target AVAudioFormat at rate=\(Int(targetSampleRate))",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      stopInternal(reason: "audio_engine_target_format_failed")
      return
    }

    let needsConversion =
      abs(inputFormat.sampleRate - targetSampleRate) > 1.0 ||
      inputFormat.channelCount != 1 ||
      inputFormat.commonFormat != .pcmFormatFloat32

    if needsConversion {
      guard let newConverter = AVAudioConverter(from: inputFormat, to: target) else {
        VoiceControlSdkPlugin.publishEvent(
          [
            "type": "error",
            "code": "audio_engine_start_failed",
            "message": "AVAudioConverter init failed: input=\(inputFormat) target=\(target)",
            "source": "ios",
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
          ]
        )
        stopInternal(reason: "audio_converter_init_failed")
        return
      }
      converter = newConverter
    } else {
      converter = nil
    }

    self.hardwareFormat = inputFormat
    self.targetFormat = target

    if tapInstalled {
      inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.handleInputBuffer(buffer)
    }
    tapInstalled = true

    do {
      try audioEngine.start()
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "state",
          "state": "waiting_for_wake",
          "message": "等待 Lumi / 鲁米 唤醒",
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
          "message": "iOS microphone capture started hwRate=\(Int(inputFormat.sampleRate)) hwChannels=\(inputFormat.channelCount) targetRate=\(Int(targetSampleRate)) converter=\(needsConversion)",
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
      // 已在 audio queue 上；同步 teardown，避免 defer 的 stop 与后续 start 交错。
      stopInternal(reason: "audio_engine_start_failed")
    }
  }

  private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
    guard isListening else { return }

    if let activeConverter = converter, let target = targetFormat {
      let ratio = target.sampleRate / max(buffer.format.sampleRate, 1.0)
      let estimated = Int((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
      let capacity = AVAudioFrameCount(max(estimated, 256))
      guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
        return
      }

      var consumed = false
      var convertError: NSError?
      let status = activeConverter.convert(to: output, error: &convertError) { _, outStatus in
        if consumed {
          outStatus.pointee = .noDataNow
          return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return buffer
      }

      switch status {
      case .haveData, .inputRanDry:
        if output.frameLength > 0 {
          emitBuffer(output, sampleRate: Int(target.sampleRate))
        }
      case .endOfStream:
        return
      case .error:
        VoiceControlSdkPlugin.publishEvent(
          [
            "type": "error",
            "code": "audio_stream_error",
            "message": convertError?.localizedDescription ?? "AVAudioConverter convert failed",
            "source": "ios",
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
          ]
        )
      @unknown default:
        return
      }
    } else {
      emitBuffer(buffer, sampleRate: Int(buffer.format.sampleRate))
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
    if frameCount == 0 {
      return
    }
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

  private func stopInternal(reason: String, discardEngineWithoutTouchingNodes: Bool = false) {
    isListening = false
    if discardEngineWithoutTouchingNodes {
      tapInstalled = false
      converter = nil
      hardwareFormat = nil
      targetFormat = nil
      audioEngine = AVAudioEngine()
    } else {
      if tapInstalled {
        if audioEngine.isRunning {
          audioEngine.inputNode.removeTap(onBus: 0)
          audioEngine.stop()
        } else {
          audioEngine.inputNode.removeTap(onBus: 0)
        }
        tapInstalled = false
      } else if audioEngine.isRunning {
        audioEngine.stop()
      }
      converter = nil
      hardwareFormat = nil
      targetFormat = nil
      audioEngine = AVAudioEngine()
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

  private func registerSessionNotificationsIfNeeded() {
    if notificationsRegistered { return }
    notificationsRegistered = true
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    center.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance()
    )
    center.addObserver(
      self,
      selector: #selector(handleMediaServicesReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: AVAudioSession.sharedInstance()
    )
    center.addObserver(
      self,
      selector: #selector(handleAppDidEnterBackground(_:)),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  @objc
  private func handleInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else {
      return
    }
    switch type {
    case .began:
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "telemetry",
          "message": "iOS audio session interrupted",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      queue.async { [weak self] in
        guard let self = self, self.isListening else { return }
        self.stopInternal(reason: "audio_session_interrupted")
      }
    case .ended:
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "telemetry",
          "message": "iOS audio session interruption ended",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
    @unknown default:
      return
    }
  }

  @objc
  private func handleRouteChange(_ notification: Notification) {
    guard let info = notification.userInfo,
          let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
    else {
      return
    }
    switch reason {
    case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override:
      VoiceControlSdkPlugin.publishEvent(
        [
          "type": "telemetry",
          "message": "iOS audio route changed reason=\(reason.rawValue)",
          "source": "ios",
          "timestampMs": Int(Date().timeIntervalSince1970 * 1000)
        ]
      )
      queue.async { [weak self] in
        guard let self = self, self.isListening else { return }
        self.stopInternal(reason: "audio_route_changed")
      }
    default:
      return
    }
  }

  @objc
  private func handleMediaServicesReset(_ notification: Notification) {
    queue.async { [weak self] in
      guard let self = self, self.isListening else { return }
      // 重置后旧引擎内部节点可能已为 nullptr，不得再调用 inputNode/removeTap。
      self.stopInternal(reason: "media_services_were_reset", discardEngineWithoutTouchingNodes: true)
    }
  }

  @objc
  private func handleAppDidEnterBackground(_ notification: Notification) {
    queue.async { [weak self] in
      guard let self = self, self.isListening else { return }
      self.stopInternal(reason: "app_entered_background")
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

struct VoiceConfig {
  let sampleRate: Int
  let wakeWord: String
  let sensitivity: Double

  init(
    sampleRate: Int = 16000,
    wakeWord: String = "Lumi",
    sensitivity: Double = 0.82
  ) {
    self.sampleRate = sampleRate
    self.wakeWord = wakeWord
    self.sensitivity = sensitivity
  }

  init(arguments: [String: Any]?) {
    let arguments = arguments ?? [:]
    self.init(
      sampleRate: (arguments["sampleRate"] as? NSNumber)?.intValue ?? 16000,
      wakeWord: (arguments["wakeWord"] as? String) ?? "Lumi",
      sensitivity: (arguments["sensitivity"] as? NSNumber)?.doubleValue ?? 0.82
    )
  }
}
