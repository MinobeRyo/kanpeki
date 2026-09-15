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
        print("Screen permission flow: 5 scenarios passed (injected API, no OS permission changed)")
    }
}
