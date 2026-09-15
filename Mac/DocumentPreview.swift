import SwiftUI
import QuickLookUI

/// A saved-document preview. Live presentation images still come from PowerPoint capture.
struct DocumentPreview: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Access { Access(url) }
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {}
    static func dismantleNSView(_ view: QLPreviewView, coordinator: Access) { view.close() }
    final class Access {
        let url: URL
        let scoped: Bool
        init(_ url: URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
        deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
    }
}

enum MacSetupStep: Equatable {
    case document, powerPoint, window, connection, time, ready
    static func next(document: Bool, screenOnly: Bool, opened: Bool, window: Bool,
                     connected: Bool, macOnly: Bool, time: Bool) -> Self {
        if !document && !screenOnly { return .document }
        if !screenOnly && !opened && !window { return .powerPoint }
        if !window { return .window }
        if !connected && !macOnly { return .connection }
        if !time { return .time }
        return .ready
    }
}
