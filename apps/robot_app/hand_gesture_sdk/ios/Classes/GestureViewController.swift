import AVFoundation
import MediaPipeTasksVision
import UIKit

final class GestureViewController: UIViewController,
  AVCaptureVideoDataOutputSampleBufferDelegate,
  HandLandmarkerLiveStreamDelegate,
  PoseLandmarkerLiveStreamDelegate
{
  private let onDismiss: () -> Void

  private let previewView = UIView()
  private let skeletonOverlayView = SkeletonOverlayView()
  private let statusLabel = UILabel()
  private let gestureLabel = UILabel()
  private let closeButton = UIButton(type: .system)

  private let captureSession = AVCaptureSession()
  private let captureQueue = DispatchQueue(label: "com.xinzhang.hand_gesture_sdk.capture")
  private let modelQueue = DispatchQueue(label: "com.xinzhang.hand_gesture_sdk.model")
  private let videoOutput = AVCaptureVideoDataOutput()

  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var handLandmarker: HandLandmarker?
  private var poseLandmarker: PoseLandmarker?
  private var lastStatusMessage: String = ""
  private var isSessionReady = false

  init(onDismiss: @escaping () -> Void) {
    self.onDismiss = onDismiss
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    captureSession.stopRunning()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureUI()
    updateStatus("正在检查相机权限...")
    requestCameraPermissionIfNeeded()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = previewView.bounds
  }

  private func configureUI() {
    previewView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewView)

    skeletonOverlayView.translatesAutoresizingMaskIntoConstraints = false
    skeletonOverlayView.setMirrorX(true)
    previewView.addSubview(skeletonOverlayView)

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.textColor = .white
    statusLabel.numberOfLines = 0
    statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
    view.addSubview(statusLabel)

    gestureLabel.translatesAutoresizingMaskIntoConstraints = false
    gestureLabel.textColor = .white
    gestureLabel.numberOfLines = 0
    gestureLabel.font = .systemFont(ofSize: 28, weight: .bold)
    gestureLabel.text = "等待相机开启..."
    view.addSubview(gestureLabel)

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.setTitle("关闭", for: .normal)
    closeButton.setTitleColor(.white, for: .normal)
    closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    view.addSubview(closeButton)

    NSLayoutConstraint.activate([
      previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      previewView.topAnchor.constraint(equalTo: view.topAnchor),
      previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      skeletonOverlayView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
      skeletonOverlayView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
      skeletonOverlayView.topAnchor.constraint(equalTo: previewView.topAnchor),
      skeletonOverlayView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),

      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

      gestureLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      gestureLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      gestureLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12)
    ])
  }

  @objc private func closeTapped() {
    dismiss(animated: true)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    captureSession.stopRunning()
    onDismiss()
  }

  private func requestCameraPermissionIfNeeded() {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      initializeRecognizersAndStart()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if granted {
            self.initializeRecognizersAndStart()
          } else {
            self.updateStatus("相机权限被拒绝")
            HandGestureSdkPlugin.publishEvent(
              type: "error",
              message: "相机权限被拒绝"
            )
          }
        }
      }
    default:
      updateStatus("相机权限被拒绝")
      HandGestureSdkPlugin.publishEvent(
        type: "error",
        message: "相机权限被拒绝"
      )
    }
  }

  private func initializeRecognizersAndStart() {
    updateStatus("正在加载内置模型...")
    modelQueue.async { [weak self] in
      guard let self = self else { return }
      do {
        guard
          let handModelPath = self.bundleModelPath(
            named: "hand_landmarker",
            subdirectory: "Models"
          ),
          let poseModelPath = self.bundleModelPath(
            named: "pose_landmarker_lite",
            subdirectory: "Models"
          )
        else {
          self.reportError("内置模型未找到")
          return
        }

        let handOptions = HandLandmarkerOptions()
        handOptions.baseOptions.modelAssetPath = handModelPath
        handOptions.runningMode = .liveStream
        handOptions.numHands = 1
        handOptions.minHandDetectionConfidence = 0.7
        handOptions.minHandPresenceConfidence = 0.7
        handOptions.minTrackingConfidence = 0.5
        handOptions.handLandmarkerLiveStreamDelegate = self
        self.handLandmarker = try HandLandmarker(options: handOptions)

        let poseOptions = PoseLandmarkerOptions()
        poseOptions.baseOptions.modelAssetPath = poseModelPath
        poseOptions.runningMode = .liveStream
        poseOptions.numPoses = 1
        poseOptions.minPoseDetectionConfidence = 0.5
        poseOptions.minPosePresenceConfidence = 0.5
        poseOptions.minTrackingConfidence = 0.5
        poseOptions.poseLandmarkerLiveStreamDelegate = self
        self.poseLandmarker = try PoseLandmarker(options: poseOptions)

        DispatchQueue.main.async {
          self.startCaptureSession()
        }
      } catch {
        DispatchQueue.main.async {
          self.reportError("识别器初始化失败：\(error.localizedDescription)")
        }
      }
    }
  }

  private func bundleModelPath(named name: String, subdirectory: String) -> String? {
    if let url = Bundle.main.url(
      forResource: name,
      withExtension: "task",
      subdirectory: subdirectory
    ) {
      return url.path
    }

    if let url = Bundle.main.url(forResource: name, withExtension: "task") {
      return url.path
    }

    return nil
  }

  private func startCaptureSession() {
    guard !isSessionReady else {
      return
    }

    captureSession.beginConfiguration()
    captureSession.sessionPreset = .high

    defer {
      captureSession.commitConfiguration()
    }

    guard
      let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
      let input = try? AVCaptureDeviceInput(device: camera),
      captureSession.canAddInput(input)
    else {
      reportError("无法打开前置摄像头")
      return
    }

    captureSession.addInput(input)

    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
    guard captureSession.canAddOutput(videoOutput) else {
      reportError("无法添加视频输出")
      return
    }
    captureSession.addOutput(videoOutput)

    let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.frame = previewView.bounds
    previewView.layer.insertSublayer(previewLayer, at: 0)
    self.previewLayer = previewLayer

    captureQueue.async { [weak self] in
      self?.captureSession.startRunning()
    }
    isSessionReady = true
    updateStatus("相机已就绪")
    HandGestureSdkPlugin.publishEvent(type: "ready", message: "相机已就绪")
    gestureLabel.text = "请展示手部"
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let handLandmarker = handLandmarker, let poseLandmarker = poseLandmarker else {
      return
    }
    guard let image = try? MPImage(sampleBuffer: sampleBuffer, orientation: .up) else {
      return
    }
    let timestamp = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000.0)
    do {
      try handLandmarker.detectAsync(image: image, timestampInMilliseconds: timestamp)
      try poseLandmarker.detectAsync(image: image, timestampInMilliseconds: timestamp)
    } catch {
      reportError("识别失败：\(error.localizedDescription)")
    }
  }

  func handLandmarker(
    _ handLandmarker: HandLandmarker,
    didFinishDetection result: HandLandmarkerResult?,
    timestampInMilliseconds timestampInMilliseconds: Int,
    error: Error?
  ) {
    if let error = error {
      reportError("手势识别失败：\(error.localizedDescription)")
      return
    }

    guard let landmarks = result?.landmarks.first, !landmarks.isEmpty else {
      updateStatus("未检测到手部")
      DispatchQueue.main.async {
        self.skeletonOverlayView.updateHandLandmarks([])
      }
      return
    }

    let gesture = classifyHandGesture(landmarks)
    let handedness = result?.handedness.first?.first?.categoryName
    let metrics = buildHandMetrics(landmarks, handedness: handedness)
    let confidence = metrics["confidence"] as? Double ?? 0.85

    DispatchQueue.main.async {
      self.gestureLabel.text = gesture
      self.skeletonOverlayView.updateHandLandmarks(self.toPoints(landmarks))
    }

    updateStatus("检测到\(handedness ?? "手")")
    HandGestureSdkPlugin.publishEvent(
      type: "gesture",
      message: gesture,
      gesture: gesture,
      confidence: confidence,
      metrics: metrics
    )
  }

  func poseLandmarker(
    _ poseLandmarker: PoseLandmarker,
    didFinishDetection result: PoseLandmarkerResult?,
    timestampInMilliseconds timestampInMilliseconds: Int,
    error: Error?
  ) {
    if let error = error {
      reportError("姿态识别失败：\(error.localizedDescription)")
      return
    }

    guard let landmarks = result?.landmarks.first, !landmarks.isEmpty else {
      DispatchQueue.main.async {
        self.skeletonOverlayView.updatePoseLandmarks([])
      }
      return
    }

    let pose = classifyPose(landmarks)
    let metrics = buildPoseMetrics(landmarks)
    let confidence = metrics["confidence"] as? Double ?? 0.8

    HandGestureSdkPlugin.publishEvent(
      type: "pose",
      message: pose,
      pose: pose,
      confidence: confidence,
      metrics: metrics
    )

    DispatchQueue.main.async {
      self.skeletonOverlayView.updatePoseLandmarks(self.toPoints(landmarks))
    }
  }

  private func classifyHandGesture(_ landmarks: [NormalizedLandmark]) -> String {
    let indexExtended = landmarks[8].y < landmarks[6].y
    let middleExtended = landmarks[12].y < landmarks[10].y
    let ringExtended = landmarks[16].y < landmarks[14].y
    let pinkyExtended = landmarks[20].y < landmarks[18].y
    let thumbExtended = landmarks[4].x > landmarks[3].x

    let extendedCount = [indexExtended, middleExtended, ringExtended, pinkyExtended].filter { $0 }.count
    let curledCount = [indexExtended, middleExtended, ringExtended, pinkyExtended].filter { !$0 }.count

    if extendedCount == 4 {
      return "张开手掌"
    }
    if curledCount == 4 {
      return "握拳"
    }
    if indexExtended && middleExtended && !ringExtended && !pinkyExtended {
      return "胜利"
    }
    if indexExtended && !middleExtended && !ringExtended && !pinkyExtended {
      return "指向"
    }
    if thumbExtended && curledCount >= 3 {
      return "点赞"
    }

    return "未知"
  }

  private func buildHandMetrics(_ landmarks: [NormalizedLandmark], handedness: String?) -> [String: Any] {
    let xs = landmarks.map { Double($0.x) }
    let ys = landmarks.map { Double($0.y) }
    let minX = xs.min() ?? 0
    let maxX = xs.max() ?? 0
    let minY = ys.min() ?? 0
    let maxY = ys.max() ?? 0
    let width = maxX - minX
    let height = maxY - minY
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2

    return [
      "handArea": width * height,
      "handCenterX": centerX,
      "handCenterY": centerY,
      "bboxWidth": width,
      "bboxHeight": height,
      "handedness": handedness ?? "unknown",
      "confidence": 0.9
    ]
  }

  private func classifyPose(_ landmarks: [NormalizedLandmark]) -> String {
    guard landmarks.count > 28 else {
      return "未知"
    }

    let leftKnee = angle(landmarks[23], landmarks[25], landmarks[27])
    let rightKnee = angle(landmarks[24], landmarks[26], landmarks[28])

    if leftKnee < 140 && rightKnee < 140 {
      return "蹲下"
    }
    if leftKnee > 160 && rightKnee > 160 {
      return "站起"
    }
    return "未知"
  }

  private func buildPoseMetrics(_ landmarks: [NormalizedLandmark]) -> [String: Any] {
    guard landmarks.count > 28 else {
      return ["confidence": 0.5]
    }

    let leftKnee = angle(landmarks[23], landmarks[25], landmarks[27])
    let rightKnee = angle(landmarks[24], landmarks[26], landmarks[28])
    let leftHip = angle(landmarks[11], landmarks[23], landmarks[25])
    let rightHip = angle(landmarks[12], landmarks[24], landmarks[26])

    return [
      "leftKneeAngle": leftKnee,
      "rightKneeAngle": rightKnee,
      "leftHipAngle": leftHip,
      "rightHipAngle": rightHip,
      "confidence": 0.8
    ]
  }

  private func angle(_ a: NormalizedLandmark, _ b: NormalizedLandmark, _ c: NormalizedLandmark) -> Double {
    let abx = Double(a.x - b.x)
    let aby = Double(a.y - b.y)
    let cbx = Double(c.x - b.x)
    let cby = Double(c.y - b.y)

    let dot = abx * cbx + aby * cby
    let magnitude = sqrt((abx * abx + aby * aby) * (cbx * cbx + cby * cby))
    guard magnitude > 0 else {
      return 0
    }

    let cosine = max(-1.0, min(1.0, dot / magnitude))
    return acos(cosine) * 180.0 / .pi
  }

  private func updateStatus(_ message: String) {
    guard lastStatusMessage != message else {
      return
    }
    DispatchQueue.main.async {
      self.lastStatusMessage = message
      self.statusLabel.text = message
      HandGestureSdkPlugin.publishEvent(type: "status", message: message)
    }
  }

  private func reportError(_ message: String) {
    updateStatus(message)
    HandGestureSdkPlugin.publishEvent(type: "error", message: message)
  }

  private func toPoints(_ landmarks: [NormalizedLandmark]) -> [CGPoint] {
    landmarks.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
  }
}
