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
    private let isRunning: () -> Bool
    private let runScript: (String) throws -> NSAppleEventDescriptor

    init(isRunning: @escaping () -> Bool = {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint").isEmpty
    }, runScript: @escaping (String) throws -> NSAppleEventDescriptor = PowerPointBridge.runAppleScript) {
        self.isRunning = isRunning
        self.runScript = runScript
    }

    private func execute(_ body: String) throws -> NSAppleEventDescriptor {
        guard isRunning() else {
            throw PowerPointError.failed("PowerPointを起動し、スライドショーを開始してください")
        }
        let source = "tell application id \"com.microsoft.Powerpoint\"\n" + body + "\nend tell"
        return try runScript(source)
    }

    static func scriptError(code: Int, message: String?) -> PowerPointError {
        switch code {
        case -1743:
            return .failed("システム設定 → プライバシーとセキュリティ → オートメーションでPowerPoint操作を許可してください")
        case -600, -609:
            return .failed("PowerPointとの接続が切れました。アプリとスライドショーを確認し、操作を有効にし直してください")
        case -1712:
            return .failed("PowerPointが応答していません。ダイアログやスライドショーを確認し、操作を有効にし直してください")
        default:
            return .failed(message?.isEmpty == false ? message! : "PowerPointとの連携に失敗しました")
        }
    }

    private static func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw PowerPointError.failed("PowerPoint操作を準備できません") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            throw scriptError(code: code, message: error[NSAppleScript.errorMessage] as? String)
        }
        return result
    }

    func readPosition() throws -> SlidePosition {
        let result = try execute("""
        if (count of slide show windows) is 0 then error "スライドショーが終了しているか、開始されていません。PowerPointで開始してください"
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
        guard result.descriptorType == typeAEList, result.numberOfItems == 5,
              let title = Self.text(result.atIndex(1)), !title.isEmpty,
              let path = Self.text(result.atIndex(2)),
              let index = Self.integer(result.atIndex(3)),
              let id = Self.integer(result.atIndex(4)),
              let count = Self.integer(result.atIndex(5)) else {
            throw PowerPointError.failed("現在のスライド情報を取得できません")
        }
        guard index > 0, count >= index, id > 0 else { throw PowerPointError.failed("スライドが表示されていません") }
        return SlidePosition(title: title, path: path, index: index, id: id, count: count)
    }

    private static func text(_ value: NSAppleEventDescriptor?) -> String? {
        guard let value, [typeUnicodeText, typeUTF8Text, typeChar].contains(value.descriptorType) else { return nil }
        return value.stringValue
    }

    private static func integer(_ value: NSAppleEventDescriptor?) -> Int? {
        guard let value, [typeSInt16, typeSInt32].contains(value.descriptorType) else { return nil }
        return Int(value.int32Value)
    }

    func move(_ action: RemoteAction) throws {
        if action == .refresh { return }
        let command = action == .next ? "go to next slide" : "go to previous slide"
        let direction = action == .next ? "1" : "-1"
        _ = try execute("""
        if (count of slide show windows) is 0 then error "スライドショーが終了しているか、開始されていません。PowerPointで開始してください"
        if (count of slide show windows) is not 1 then error "スライドショーを1つだけ開いてください"
        set w to slide show window 1
        set p to presentation of w
        set v to slideshow view of w
        set currentIndex to slide index of (slide of v)
        set slideCount to count of slides of p
        if currentIndex < 1 or currentIndex > slideCount then error "現在のスライドを確認してください"
        set settings to slide show settings of p
        if (is named show of v) or (range type of settings is slide show range named slideshow) then error "目的別スライドショーの送り戻りは未対応です。PowerPointで操作してください"
        set firstIndex to 1
        set lastIndex to slideCount
        if range type of settings is slide show range then
            set firstIndex to starting slide of settings
            set lastIndex to ending slide of settings
        end if
        if firstIndex < 1 or lastIndex > slideCount or firstIndex > lastIndex then error "スライドショーの範囲を確認してください"
        if currentIndex < firstIndex or currentIndex > lastIndex then error "スライドショーの範囲を確認してください"
        set candidateIndex to currentIndex + (\(direction))
        repeat while candidateIndex >= firstIndex and candidateIndex <= lastIndex
            if not (hidden of slide show transition of slide candidateIndex of p) then
                \(command) v
                return
            end if
            set candidateIndex to candidateIndex + (\(direction))
        end repeat
        -- No next/previous visible slide: do not wrap or end the show.
        """)
    }
}
