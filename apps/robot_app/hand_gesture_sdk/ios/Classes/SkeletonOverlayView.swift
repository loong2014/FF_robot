import UIKit

final class SkeletonOverlayView: UIView {
  private let handConnectionColor = UIColor(red: 1.0, green: 0.71, blue: 0.29, alpha: 0.95)
  private let poseConnectionColor = UIColor(red: 0.27, green: 0.84, blue: 1.0, alpha: 0.95)
  private let handNodeFillColor = UIColor(red: 1.0, green: 0.91, blue: 0.65, alpha: 0.98)
  private let poseNodeFillColor = UIColor(red: 0.90, green: 1.0, blue: 1.0, alpha: 0.98)
  private let handNodeStrokeColor = UIColor(red: 0.31, green: 0.19, blue: 0.0, alpha: 0.9)
  private let poseNodeStrokeColor = UIColor(red: 0.0, green: 0.35, blue: 0.42, alpha: 0.9)

  private var handLandmarks: [CGPoint] = []
  private var poseLandmarks: [CGPoint] = []
  private var mirrorX = true

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    backgroundColor = .clear
    contentMode = .redraw
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setMirrorX(_ enabled: Bool) {
    mirrorX = enabled
    setNeedsDisplay()
  }

  func updateHandLandmarks(_ points: [CGPoint]?) {
    handLandmarks = points ?? []
    setNeedsDisplay()
  }

  func updatePoseLandmarks(_ points: [CGPoint]?) {
    poseLandmarks = points ?? []
    setNeedsDisplay()
  }

  func clear() {
    handLandmarks = []
    poseLandmarks = []
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else {
      return
    }

    if !handLandmarks.isEmpty {
      drawConnections(
        in: context,
        points: handLandmarks,
        connections: Self.handConnections,
        strokeColor: handConnectionColor,
        lineWidth: 6
      )
      drawNodes(
        in: context,
        points: handLandmarks,
        fillColor: handNodeFillColor,
        strokeColor: handNodeStrokeColor,
        radius: 12
      )
    }

    if !poseLandmarks.isEmpty {
      drawConnections(
        in: context,
        points: poseLandmarks,
        connections: Self.poseConnections,
        strokeColor: poseConnectionColor,
        lineWidth: 5
      )
      drawNodes(
        in: context,
        points: poseLandmarks,
        fillColor: poseNodeFillColor,
        strokeColor: poseNodeStrokeColor,
        radius: 9
      )
    }
  }

  private func drawConnections(
    in context: CGContext,
    points: [CGPoint],
    connections: [[Int]],
    strokeColor: UIColor,
    lineWidth: CGFloat
  ) {
    context.saveGState()
    context.setStrokeColor(strokeColor.cgColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    for connection in connections {
      guard connection.count >= 2 else { continue }
      let startIndex = connection[0]
      let endIndex = connection[1]
      guard startIndex < points.count, endIndex < points.count else { continue }
      let start = mapPoint(points[startIndex])
      let end = mapPoint(points[endIndex])
      context.beginPath()
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()
    }

    context.restoreGState()
  }

  private func drawNodes(
    in context: CGContext,
    points: [CGPoint],
    fillColor: UIColor,
    strokeColor: UIColor,
    radius: CGFloat
  ) {
    context.saveGState()

    for point in points {
      let mapped = mapPoint(point)
      let rect = CGRect(x: mapped.x - radius, y: mapped.y - radius, width: radius * 2, height: radius * 2)
      context.setFillColor(fillColor.cgColor)
      context.fillEllipse(in: rect)
      context.setStrokeColor(strokeColor.cgColor)
      context.setLineWidth(2)
      context.strokeEllipse(in: rect)
    }

    context.restoreGState()
  }

  private func mapPoint(_ point: CGPoint) -> CGPoint {
    let x = mirrorX ? bounds.width * (1 - point.x) : bounds.width * point.x
    let y = bounds.height * point.y
    return CGPoint(x: x, y: y)
  }

  private static let handConnections: [[Int]] = [
    [0, 1], [1, 2], [2, 3], [3, 4],
    [0, 5], [5, 6], [6, 7], [7, 8],
    [5, 9], [9, 10], [10, 11], [11, 12],
    [9, 13], [13, 14], [14, 15], [15, 16],
    [13, 17], [17, 18], [18, 19], [19, 20],
    [0, 17]
  ]

  private static let poseConnections: [[Int]] = [
    [0, 1], [1, 2], [2, 3], [3, 7],
    [0, 4], [4, 5], [5, 6], [6, 8],
    [9, 10], [11, 12], [11, 13], [13, 15], [15, 17], [15, 19], [15, 21],
    [17, 19], [12, 14], [14, 16], [16, 18], [16, 20], [16, 22], [18, 20],
    [11, 23], [12, 24], [23, 24], [23, 25], [25, 27], [27, 29], [29, 31],
    [24, 26], [26, 28], [28, 30], [30, 32], [27, 31], [28, 32]
  ]
}
