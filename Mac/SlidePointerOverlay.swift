import AppKit

/// A non-activating, click-through laser dot. No Accessibility or synthetic mouse access.
@MainActor final class SlidePointerOverlay {
    private let panel: NSPanel
    private var expiry: DispatchWorkItem?
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = DotView()
    }
    func clear() { expiry?.cancel(); expiry = nil; panel.orderOut(nil) }
    func show(_ point: SlidePointerPoint, windowID: CGWindowID) {
        guard point.isValid,
              let windows = CGWindowListCopyWindowInfo([.optionIncludingWindow, .excludeDesktopElements], windowID) as? [[String: Any]],
              let info = windows.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let owner = info[kCGWindowOwnerPID as String] as? Int32,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == owner,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              let primary = NSScreen.screens.first else { clear(); return }
        guard frame.width > 14, frame.height > 14 else { clear(); return }
        let x = min(frame.maxX - 7, max(frame.minX + 7, frame.minX + point.x * frame.width))
        let topY = min(frame.maxY - 7, max(frame.minY + 7, frame.minY + point.y * frame.height))
        // Do not draw above another application's window, a menu, or a different PPT window.
        guard let stack = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let targetIndex = stack.firstIndex(where: { ($0[kCGWindowNumber as String] as? UInt32) == windowID }) else { clear(); return }
        for item in stack.prefix(targetIndex) {
            if item[kCGWindowOwnerPID as String] as? Int32 == ProcessInfo.processInfo.processIdentifier { continue }
            if let bounds = item[kCGWindowBounds as String] as? NSDictionary,
               let above = CGRect(dictionaryRepresentation: bounds), above.contains(CGPoint(x: x, y: topY)) {
                clear(); return
            }
        }
        let y = primary.frame.maxY - topY
        panel.setFrame(CGRect(x: x - 7, y: y - 7, width: 14, height: 14), display: true)
        panel.orderFrontRegardless()
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clear() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private final class DotView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
            NSColor.white.setStroke()
            let edge = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            edge.lineWidth = 2
            edge.stroke()
        }
    }
}
