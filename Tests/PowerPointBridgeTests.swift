import AppKit

@main struct PowerPointBridgeTests {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
        print("PASS: \(message)")
    }
    static func descriptor(_ fields: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let value = NSAppleEventDescriptor.list()
        for (index, field) in fields.enumerated() { value.insert(field, at: index + 1) }
        return value
    }
    static func main() throws {
        let valid: [NSAppleEventDescriptor] = [.init(string: "研究発表"), .init(string: "/資料/研究.pptx"),
                                              .init(int32: 2), .init(int32: 256), .init(int32: 4)]
        var response = descriptor(valid)
        var scripts: [String] = []
        let bridge = PowerPointBridge(isRunning: { true }, runScript: { scripts.append($0); return response })
        let position = try bridge.readPosition()
        expect(position.title == "研究発表" && position.path == "/資料/研究.pptx", "preserve source title and path")
        expect(position.index == 2 && position.id == 256 && position.count == 4, "preserve source slide identity")
        func rejects(_ fields: [NSAppleEventDescriptor], _ message: String) {
            response = descriptor(fields)
            do { _ = try bridge.readPosition(); preconditionFailure(message) }
            catch { expect(error is PowerPointError, message) }
        }
        rejects(Array(valid.prefix(4)), "reject missing fields")
        rejects(valid + [.init(int32: 1)], "reject extra fields")
        for fieldIndex in 2...4 {
            var fields = valid; fields[fieldIndex] = .init(string: "2")
            rejects(fields, "reject coerced string integer at field \(fieldIndex)")
            fields[fieldIndex] = .init(boolean: true)
            rejects(fields, "reject boolean integer at field \(fieldIndex)")
        }
        var fields = valid; fields[2] = .init(int32: 0)
        rejects(fields, "reject zero index after show ends")
        fields = valid; fields[2] = .init(int32: 5)
        rejects(fields, "reject out-of-range position")
        fields = valid; fields[3] = .init(int32: -1)
        rejects(fields, "reject invalid source slide ID")
        fields = valid; fields[0] = .init(int32: 42)
        rejects(fields, "reject coerced nontext title")
        fields = valid; fields[0] = .init(string: "")
        rejects(fields, "reject empty presentation title")
        var invoked = false
        let stopped = PowerPointBridge(isRunning: { false }, runScript: { _ in invoked = true; return response })
        do { _ = try stopped.readPosition(); preconditionFailure("Must reject stopped application") }
        catch { expect(error.localizedDescription.contains("起動"), "explain PowerPoint not running") }
        expect(!invoked, "never execute or launch PowerPoint when not running")
        try stopped.move(.refresh)
        expect(!invoked, "refresh does not send an AppleEvent")
        expect(PowerPointBridge.scriptError(code: -1743, message: nil).localizedDescription.contains("オートメーション"), "permission recovery guidance")
        expect(PowerPointBridge.scriptError(code: -600, message: nil).localizedDescription.contains("接続が切れ"), "application quit guidance")
        expect(PowerPointBridge.scriptError(code: -609, message: nil).localizedDescription.contains("接続が切れ"), "broken connection guidance")
        expect(PowerPointBridge.scriptError(code: -1712, message: nil).localizedDescription.contains("応答していません"), "timeout recovery guidance")
        expect(PowerPointBridge.scriptError(code: 99, message: "").localizedDescription == "PowerPointとの連携に失敗しました", "empty errors get fallback")
        expect(PowerPointBridge.scriptError(code: 99, message: "ショーを確認").localizedDescription == "ショーを確認", "preserve actionable script errors")

        // These are generated-script contract checks, not an execution of PowerPoint's dictionary.
        scripts = []
        try bridge.move(.next)
        expect(scripts.count == 1, "navigation checks and command are sent in one script")
        let next = scripts[0]
        expect(next.contains("currentIndex + (1)"), "next scans forward")
        expect(next.contains("candidateIndex >= firstIndex and candidateIndex <= lastIndex"), "guard show range before moving")
        expect(next.contains("hidden of slide show transition"), "skip hidden end slides when deciding whether next is safe")
        expect(next.contains("slide show range named slideshow"), "reject unsupported custom ordering")
        expect(next.contains("starting slide of settings") && next.contains("ending slide of settings"), "honor configured show range")
        expect(next.contains("if (count of slide show windows) is 0") && next.contains("is not 1"), "separate stopped and ambiguous shows")
        expect(next.contains("go to next slide v\n        return"), "only navigate inside an in-range visible candidate branch")
        scripts = []
        try bridge.move(.previous)
        expect(scripts[0].contains("currentIndex + (-1)") && scripts[0].contains("go to previous slide v"), "previous scans backward")
        let failed = PowerPointBridge(isRunning: { true }, runScript: { _ in throw PowerPointBridge.scriptError(code: -1743, message: nil) })
        do { try failed.move(.next); preconditionFailure("Must propagate executor error") }
        catch { expect(error.localizedDescription.contains("オートメーション"), "propagate navigation failure without retry") }
        print("\(checks) PowerPoint bridge checks passed (synthetic; no PowerPoint automation)")
    }
}
