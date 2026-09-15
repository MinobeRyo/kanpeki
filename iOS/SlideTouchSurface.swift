import SwiftUI
import UIKit

struct SlideTouchSurface: UIViewRepresentable {
    let imageSize: CGSize
    let enabled: Bool
    let sessionID: UUID?
    let onPointer: (SlidePointerPoint?) -> Void
    let onTap: (RemoteAction) -> Void

    func makeUIView(context: Context) -> TouchView { TouchView() }
    func updateUIView(_ view: TouchView, context: Context) {
        if !enabled || view.sessionID != sessionID || view.imageSize != imageSize { view.cancel() }
        view.imageSize = imageSize
        view.enabled = enabled
        view.sessionID = sessionID
        view.onPointer = onPointer
        view.onTap = onTap
    }
    static func dismantleUIView(_ view: TouchView, coordinator: ()) { view.cancel() }

    final class TouchView: UIView {
        var imageSize = CGSize.zero
        var enabled = false
        var sessionID: UUID?
        var onPointer: ((SlidePointerPoint?) -> Void)?
        var onTap: ((RemoteAction) -> Void)?
        private var intent = SlideTouchIntent()
        private var activeTouch: UITouch?
        private var showing = false
        private var previousBounds = CGRect.zero
        private var slideRect: CGRect { SlidePointerPoint.fittedRect(image: imageSize, bounds: bounds) }
        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds != previousBounds { cancel(); previousBounds = bounds }
        }
        func cancel() {
            intent.cancel()
            if showing { onPointer?(nil) }
            showing = false
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil, event?.allTouches?.count == 1, let touch = touches.first else { cancel(); return }
            activeTouch = touch
            intent.begin(touch.location(in: self), at: touch.timestamp, rect: slideRect, touches: 1, enabled: enabled)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch else { return }
            let location = touch.location(in: self)
            if !slideRect.contains(location) || event?.allTouches?.count != 1 || !enabled { cancel(); return }
            if let point = intent.move(location, at: touch.timestamp, rect: slideRect, touches: 1, enabled: enabled) {
                showing = true
                onPointer?(point)
            }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = activeTouch, touches.contains(touch) else { return }
            let action = intent.end(touch.location(in: self), at: touch.timestamp, rect: slideRect, enabled: enabled)
            if showing { onPointer?(nil) }
            showing = false
            activeTouch = nil
            if let action { onTap?(action) }
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancel(); activeTouch = nil }
    }
}
