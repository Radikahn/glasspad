import AppKit

/// A cursor that smears between positions, after smear-cursor.nvim.
///
/// Each corner of the cursor quad chases its target independently. Corners on
/// the leading edge of the motion are stiff and arrive almost at once, while
/// the trailing corners lag behind, stretching the cursor into a streak that
/// snaps back together as it lands.
struct SmearCursor {
    static let headStiffness: CGFloat = 0.6
    static let tailStiffness: CGFloat = 0.26
    static let stopDistance: CGFloat = 0.15

    /// top-left, top-right, bottom-right, bottom-left
    private(set) var corners: [CGPoint] = []
    private var targets: [CGPoint] = []
    private var stiffness: [CGFloat] = Array(repeating: headStiffness, count: 4)
    private(set) var isAnimating = false
    var isHidden = false

    var isInitialized: Bool { corners.count == 4 }

    var targetRect: CGRect {
        guard targets.count == 4 else { return .zero }
        return CGRect(x: targets[0].x, y: targets[0].y,
                      width: targets[2].x - targets[0].x, height: targets[2].y - targets[0].y)
    }

    var bounds: CGRect {
        guard isInitialized, !isHidden else { return .null }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    mutating func move(to rect: CGRect, animated: Bool) {
        let next = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        guard animated, isInitialized else {
            corners = next
            targets = next
            isAnimating = false
            return
        }
        guard next != targets else { return }
        targets = next

        let from = Self.centroid(corners), to = Self.centroid(next)
        let dx = to.x - from.x, dy = to.y - from.y
        let distance = hypot(dx, dy)
        if distance < 0.5 {
            stiffness = Array(repeating: Self.headStiffness, count: 4)
        } else {
            // Rank corners by how far they sit along the direction of travel.
            let projections = next.map { ($0.x - to.x) * dx / distance + ($0.y - to.y) * dy / distance }
            let lo = projections.min()!, hi = projections.max()!
            stiffness = projections.map { p in
                let t = hi - lo > 0.001 ? (p - lo) / (hi - lo) : 1
                return Self.tailStiffness + (Self.headStiffness - Self.tailStiffness) * t
            }
        }
        isAnimating = true
    }

    /// Advances the animation; returns whether it is still running.
    mutating func step(dt: CFTimeInterval) -> Bool {
        guard isAnimating else { return false }
        let frames = CGFloat(dt * 60)
        var remaining: CGFloat = 0
        for i in 0..<4 {
            let k = 1 - pow(1 - stiffness[i], frames)
            corners[i].x += (targets[i].x - corners[i].x) * k
            corners[i].y += (targets[i].y - corners[i].y) * k
            remaining = max(remaining, hypot(targets[i].x - corners[i].x, targets[i].y - corners[i].y))
        }
        if remaining < Self.stopDistance {
            corners = targets
            isAnimating = false
        }
        return isAnimating
    }

    func path() -> NSBezierPath {
        guard isAnimating else {
            return NSBezierPath(roundedRect: targetRect, xRadius: 1.5, yRadius: 1.5)
        }
        let path = NSBezierPath()
        path.move(to: corners[0])
        for corner in corners.dropFirst() { path.line(to: corner) }
        path.close()
        return path
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }
}
