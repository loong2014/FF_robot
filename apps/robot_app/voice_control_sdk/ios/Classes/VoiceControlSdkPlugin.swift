import AVFoundation
import Flutter
import UIKit

public class VoiceControlSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static var shared: VoiceControlSdkPlugin?

  private var eventSink: FlutterEventSink?
  private var coordinator: VoiceListeningCoordinator?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VoiceControlSdkPlugin()
    shared = instance

    let methodChannel = FlutterMethodChannel(
      name: "voice_control_sdk",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: "voice_control_sdk/events",
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS \(UIDevice.current.systemVersion)")
    case "ensurePermissions":
      ensurePermissions(result: result)
    case "startListening":
      startListening(arguments: call.arguments, result: result)
    case "stopListening":
      coordinator?.stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func startListening(arguments: Any?, result: @escaping FlutterResult) {
    let config = VoiceConfig(arguments: arguments as? [String: Any])
    if coordinator == nil {
      coordinator = VoiceListeningCoordinator()
    }
    coordinator?.start(config: config)
    result(nil)
  }

  private func ensurePermissions(result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      result(true)
    case .denied:
      result(false)
    case .undetermined:
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }
    @unknown default:
      result(false)
    }
  }

  private func emitEvent(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  public static func publishEvent(_ payload: [String: Any]) {
    shared?.emitEvent(payload)
  }
}
