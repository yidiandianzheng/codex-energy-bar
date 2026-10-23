import Foundation

/// Coordinates are screen points, independent of the panel's visual scale.
struct CompactPointerTracking {
    let start: CGPoint
    let target: CompactActionTarget?
    private(set) var isDragging = false

    mutating func update(to point: CGPoint) {
        if hypot(point.x - start.x, point.y - start.y) > 4 {
            isDragging = true
        }
    }

    mutating func finish(at point: CGPoint, target releaseTarget: CompactActionTarget?) -> CompactActionTarget? {
        update(to: point)
        return !isDragging && target == releaseTarget ? target : nil
    }
}
