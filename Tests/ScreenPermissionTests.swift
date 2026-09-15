import Foundation
import ScreenCaptureKit

@main struct ScreenPermissionTests {
    @MainActor static func main() async {
        var calls = 0
        var failure: Error?
        let capture = WindowCapture(preflightAccess: { false }, shareableWindows: {
            calls += 1
            if let failure { throw failure }
            return []
        })
        await capture.refreshWindows()
        precondition(calls == 0, "Startup must not request permission")
        await capture.refreshWindows(requestPermission: true)
        precondition(calls == 1 && !capture.needsScreenPermission, "Explicit retry must use SCK even when preflight says no")
        failure = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        await capture.refreshWindows(requestPermission: true)
        precondition(capture.needsScreenPermission && capture.message.contains("⌘Q"))
        failure = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue)
        await capture.refreshWindows(requestPermission: true)
        precondition(!capture.needsScreenPermission, "General failures must not masquerade as permission denial")
        failure = nil
        await capture.refreshWindows(requestPermission: true)
        precondition(!capture.needsScreenPermission && !capture.refreshing)
        await capture.start(windowID: 123, processID: 456)
        precondition(calls == 5 && !capture.sharing && capture.windows.isEmpty)
        precondition(!capture.needsScreenPermission && capture.message.contains("選び直し"), "Disappeared windows must return to selection, not request permission")
        failure = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        await capture.start(windowID: 123, processID: 456)
        precondition(capture.needsScreenPermission && !capture.sharing, "Start must revalidate OS permission")
        var pending: CheckedContinuation<[SCWindow], Error>?
        let delayed = WindowCapture(preflightAccess: { true }, shareableWindows: {
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        let starting = Task { await delayed.start(windowID: 123, processID: 456) }
        while pending == nil { await Task.yield() }
        await delayed.stop()
        pending?.resume(throwing: NSError(domain: "CoreGraphicsErrorDomain", code: 1003))
        await starting.value
        precondition(!delayed.sharing && delayed.message == "共有停止", "A late failed lookup must not overwrite cancellation")
        print("Capture start: missing target, permission denial and cancelled lookup passed")
        print("Screen permission flow: 5 scenarios passed (injected API, no OS permission changed)")
    }
}
