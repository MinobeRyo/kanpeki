import AppKit

struct SlidePosition {
    let title: String
    let path: String
    let index: Int
    let id: Int
    let count: Int
}

protocol PresentationControlling {
    func readPosition() throws -> SlidePosition
    func move(_ action: RemoteAction) throws
}

enum PowerPointError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let value) = self { return value }; return nil }
}

/// This adapter alone knows the application's scripting dictionary. Capture and networking are independent.
final class PowerPointBridge: PresentationControlling {
    private func execute(_ body: String) throws -> NSAppleEventDescriptor {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").isEmpty == false else {
            throw PowerPointError.failed("PowerPointを起動し、スライドショーを開始してください")
        }
        let source = "tell application id \"com.microsoft.Powerpoint\"\n" + body + "\nend tell"
        guard let script = NSAppleScript(source: source) else { throw PowerPointError.failed("PowerPoint操作を準備できません") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw PowerPointError.failed("システム設定 → プライバシーとセキュリティ → オートメーションでPowerPoint操作を許可してください") }
            throw PowerPointError.failed(error[NSAppleScript.errorMessage] as? String ?? "PowerPointとの連携に失敗しました")
        }
        return result
    }

    func readPosition() throws -> SlidePosition {
        let result = try execute("""
        if (count of slide show windows) is not 1 then error "PowerPointのスライドショーを1つだけ開いてください"
        set w to slide show window 1
        set p to presentation of w
        set v to slideshow view of w
        set s to slide of v
        set savedPath to full name of p
        try
            set savedPath to POSIX path of (savedPath as alias)
        end try
        return {name of p, savedPath, slide index of s, slide ID of s, count of slides of p}
        """)
        guard result.numberOfItems == 5,
              let title = result.atIndex(1)?.stringValue, let path = result.atIndex(2)?.stringValue else {
            throw PowerPointError.failed("現在のスライド情報を取得できません")
        }
        let index = Int(result.atIndex(3)?.int32Value ?? 0)
        let id = Int(result.atIndex(4)?.int32Value ?? 0)
        let count = Int(result.atIndex(5)?.int32Value ?? 0)
        guard index > 0, count >= index, id > 0 else { throw PowerPointError.failed("スライドが表示されていません") }
        return SlidePosition(title: title, path: path, index: index, id: id, count: count)
    }

    func move(_ action: RemoteAction) throws {
        if action == .refresh { return }
        let command = action == .next ? "go to next slide" : "go to previous slide"
        _ = try execute("""
        if (count of slide show windows) is not 1 then error "スライドショーを1つだけ開いてください"
        \(command) (slideshow view of slide show window 1)
        """)
    }
}
