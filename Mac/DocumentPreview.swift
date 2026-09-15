import SwiftUI
import QuickLookUI
import QuickLookThumbnailing

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

// Navigation owns only destinations. Going back never resets a presentation or receiver.
enum MacDestination: Equatable { case home, presentation, connection, analysis, audio, practice }
struct MacNavigation {
    private(set) var history: [MacDestination] = [.home]
    var current: MacDestination { history.last ?? .home }
    mutating func open(_ destination: MacDestination) {
        guard destination != current else { return }
        if let index = history.firstIndex(of: destination) { history = Array(history.prefix(index + 1)) }
        else { history.append(destination) }
    }
    mutating func back() { if history.count > 1 { history.removeLast() } }
    mutating func home() { history = [.home] }
}

struct DocumentThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
            else if failed { Label("「準備・機能」から資料を大きく表示できます", systemImage: "doc.richtext") }
            else { ProgressView("資料を表示しています…") }
        }.task(id: url) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 1200, height: 800), scale: 1, representationTypes: .thumbnail)
            do {
                let result = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled else { return }
                thumbnail = result.nsImage
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
