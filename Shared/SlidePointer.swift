import Foundation
import CoreGraphics

struct SlidePointerPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }

    static func normalized(_ point: CGPoint, in rect: CGRect) -> Self? {
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return Self(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
    static func fittedRect(image: CGSize, bounds: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

struct SlidePointerUpdate: Codable {
    let sessionID: UUID
    let sequence: UInt64
    /// Absolute normalized slide coordinates; nil clears. Never moves the OS cursor.
    let point: SlidePointerPoint?
}

struct SlidePointerReceiver {
    private var sequence: UInt64 = 0
    mutating func accept(_ update: SlidePointerUpdate, sessionID: UUID?) -> Bool {
        guard update.sessionID == sessionID, update.sequence > sequence,
              update.point?.isValid ?? true else { return false }
        sequence = update.sequence
        return true
    }
}

/// Geometry and intent are independent of UIKit so all cancel paths can be regression tested.
struct SlideTouchIntent {
    private var start: CGPoint?
    private var startedAt = 0.0
    private(set) var dragging = false
    private var cancelled = false
    private var lastSent = -Double.infinity
    mutating func begin(_ point: CGPoint, at time: Double, rect: CGRect, touches: Int, enabled: Bool) {
        self = Self()
        guard enabled, touches == 1, rect.contains(point) else { cancelled = true; return }
        start = point
        startedAt = time
    }
    mutating func cancel() { cancelled = true }
    mutating func move(_ point: CGPoint, at time: Double, rect: CGRect, touches: Int, enabled: Bool) -> SlidePointerPoint? {
        guard !cancelled, let start, enabled, touches == 1,
              let normalized = SlidePointerPoint.normalized(point, in: rect) else { cancel(); return nil }
        if hypot(point.x - start.x, point.y - start.y) > 8 { dragging = true }
        guard dragging, time - lastSent >= 1.0 / 30 else { return nil }
        lastSent = time
        return normalized
    }
    mutating func end(_ point: CGPoint, at time: Double, rect: CGRect, enabled: Bool) -> RemoteAction? {
        defer { self = Self() }
        guard !cancelled, !dragging, let start, enabled, rect.contains(point),
              hypot(point.x - start.x, point.y - start.y) <= 8,
              time >= startedAt, time - startedAt < 0.5 else { return nil }
        return point.x < rect.midX ? .previous : .next
    }
}
