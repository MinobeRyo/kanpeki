import AppKit
import SwiftUI

/// A window-scoped monitor leaves editing, sheets and modified keys to AppKit.
struct MacSlideKeyboard: NSViewRepresentable {
    let model: MacModel
    var onNarrowWindow: () -> Void

    func makeNSView(context: Context) -> KeyboardView { KeyboardView(model: model, onNarrowWindow: onNarrowWindow) }
    func updateNSView(_ view: KeyboardView, context: Context) { view.model = model; view.onNarrowWindow = onNarrowWindow }

    final class KeyboardView: NSView {
        weak var model: MacModel?
        private var monitor: Any?
        private var resizeObserver: NSObjectProtocol?
        private var wasNarrow = false
        var onNarrowWindow: () -> Void

        init(model: MacModel, onNarrowWindow: @escaping () -> Void) {
            self.model = model; self.onNarrowWindow = onNarrowWindow; super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver); self.resizeObserver = nil }
            guard window != nil else { return }
            resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.checkWindowWidth() }
                }
            Task { @MainActor [weak self] in self?.checkWindowWidth() }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, let model = self.model else { return event }
                let editing = (window.firstResponder as? NSTextView)?.isEditable == true || window.firstResponder is NSTextField
                guard MacPresentationKeyboard.canNavigate(isKeyWindow: window.isKeyWindow,
                    editingText: editing, hasSheet: window.attachedSheet != nil || NSApp.modalWindow != nil,
                    hasModifiers: !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                    isRepeating: event.isARepeat), event.keyCode == 123 || event.keyCode == 124 else { return event }
                let action: RemoteAction = event.keyCode == 123 ? .previous : .next
                guard model.state.frameReady == true, model.state.canMoveSlide(action) else { return event }
                model.move(action)
                return nil
            }
        }

        private func checkWindowWidth() {
            let narrow = window.map { $0.frame.width < 1100 } ?? false
            if narrow && !wasNarrow { onNarrowWindow() }
            wasNarrow = narrow
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        }
    }
}
