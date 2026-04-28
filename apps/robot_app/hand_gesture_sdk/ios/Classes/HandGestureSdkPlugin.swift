import Flutter
import UIKit

public class HandGestureSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static var shared: HandGestureSdkPlugin?

  private var eventSink: FlutterEventSink?
  private weak var gestureViewController: GestureViewController?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = HandGestureSdkPlugin()
    shared = instance

    let methodChannel = FlutterMethodChannel(
      name: "hand_gesture_sdk",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: "hand_gesture_sdk/events",
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS \(UIDevice.current.systemVersion)")
    case "startRecognition":
      startRecognition(result: result)
    case "stopRecognition":
      stopRecognition()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func startRecognition(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result(FlutterError(code: "plugin_unavailable", message: "Plugin instance is unavailable.", details: nil))
        return
      }

      guard self.gestureViewController == nil else {
        result(nil)
        return
      }

      guard let presenter = Self.topViewController() else {
        result(FlutterError(code: "no_view_controller", message: "Unable to find a view controller to present gesture UI.", details: nil))
        return
      }

      let controller = GestureViewController(onDismiss: { [weak self] in
        self?.gestureViewController = nil
      })

      self.gestureViewController = controller
      presenter.present(controller, animated: true)
      result(nil)
    }
  }

  private func stopRecognition() {
    DispatchQueue.main.async { [weak self] in
      self?.gestureViewController?.dismiss(animated: true)
      self?.gestureViewController = nil
    }
  }

  private func emitEvent(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  public static func publishEvent(
    type: String,
    message: String,
    gesture: String? = nil,
    pose: String? = nil,
    confidence: Double? = nil,
    metrics: [String: Any]? = nil
  ) {
    guard let shared = shared else {
      return
    }
    var payload: [String: Any] = [
      "type": type,
      "message": message
    ]
    if let gesture = gesture, !gesture.isEmpty {
      payload["gesture"] = gesture
    }
    if let pose = pose, !pose.isEmpty {
      payload["pose"] = pose
    }
    if let confidence = confidence {
      payload["confidence"] = confidence
    }
    if let metrics = metrics, !metrics.isEmpty {
      payload["metrics"] = metrics
    }
    shared.emitEvent(payload)
  }

  private static func topViewController() -> UIViewController? {
    let connectedScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = connectedScenes.flatMap { $0.windows }
    let keyWindow = windows.first { $0.isKeyWindow }
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
