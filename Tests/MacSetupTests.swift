import Foundation

@main struct MacSetupTests {
    static func main() {
        func step(document: Bool = true, screenOnly: Bool = false, opened: Bool = true, window: Bool = true,
                  connected: Bool = true, macOnly: Bool = false, time: Bool = true) -> MacSetupStep {
            .next(document:document, screenOnly:screenOnly, opened:opened, window:window, connected:connected, macOnly:macOnly, time:time)
        }
        precondition(step(document:false,opened:false,window:false,connected:false,time:false) == .document)
        precondition(step(opened:false,window:false,connected:false,time:false) == .powerPoint)
        precondition(step(window:false,connected:false,time:false) == .window)
        precondition(step(connected:false,time:false) == .connection)
        precondition(step(connected:false,macOnly:true,time:false) == .time)
        precondition(step(time:false) == .time)
        precondition(step() == .ready)
        precondition(step(opened:false) == .ready, "A manually selected window must not require relaunching PowerPoint")
        precondition(step(document:false,screenOnly:true,opened:false,window:false) == .window)
        precondition(step(document:false,screenOnly:true,opened:false) == .ready)
        precondition(step(connected:false) == .connection, "Disconnect must restore the required step")
        precondition(step(window:false) == .window, "A vanished window must not remain ready")
        print("12 Mac preparation routing checks passed")
    }
}
