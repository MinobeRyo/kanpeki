import Foundation

extension CoreTests {
    static func testSlideFrames() throws {
        let one = SlideFrameIdentity(sessionID: UUID(), revision: 1, slideID: 100, slideIndex: 1)
        var two = one
        two.revision = 2; two.slideID = 200; two.slideIndex = 2
        let data = Data([0xff, 0xd8, 0xff, 0xd9])
        func frame(_ identity: SlideFrameIdentity, _ sequence: UInt64) -> SlideFramePacket {
            SlideFramePacket(header: SlideFrameHeader(sequence: sequence, identity: identity), jpeg: data)
        }
        var state = PresentationState()
        state.isSharing = true; state.frameIdentity = one; state.frameReady = true
        var receiver = SlideFrameReceiver()
        expect(receiver.accept(frame(one, 1), state: state), "matching page frame displays")
        expect(receiver.matches(state), "matching frame enables interaction")
        expect(!receiver.accept(frame(one, 1), state: state), "duplicate frame rejected")
        state.frameIdentity = two; state.frameReady = false
        receiver.update(state: state)
        expect(!receiver.matches(state), "page transition immediately hides old frame")
        expect(!receiver.accept(frame(one, 3), state: state), "old page image cannot be relabelled")
        expect(!receiver.accept(frame(two, 4), state: state), "pending capture is not current")
        state.frameReady = true
        expect(receiver.accept(frame(two, 5), state: state), "new page frame restores display")
        expect(!receiver.accept(frame(two, 4), state: state), "reordered frame rejected")
        var reconnect = two; reconnect.sessionID = UUID()
        state.frameIdentity = reconnect
        receiver.update(state: state)
        expect(!receiver.accept(frame(two, 6), state: state), "old connection image rejected even on same page")
        expect(receiver.accept(frame(reconnect, 7), state: state), "fresh connection image accepted")
        state.isSharing = false; receiver.update(state: state)
        expect(!receiver.matches(state) && !receiver.accept(frame(reconnect, 8), state: state), "sharing stop clears and rejects late image")
        let lease = SlideCaptureLease(identity: one, beganAt: 10)
        expect(lease.accepts(current: one, now: 10.5), "current fresh screenshot lease accepted")
        expect(!lease.accepts(current: two, now: 10.5), "in-flight capture from earlier page discarded")
        expect(!lease.accepts(current: one, now: 12), "slow screenshot never renews freshness")
        expect(!lease.accepts(current: one, now: 9), "negative elapsed time cannot be fresh")
        expect(!lease.accepts(current: one, now: .nan), "nonfinite elapsed time rejected")
        var requests = SlideCaptureRequests()
        let oldRequest = requests.begin()!
        expect(requests.begin() == nil, "only one screenshot request per generation")
        requests.invalidate()
        let newRequest = requests.begin()!
        expect(newRequest != oldRequest, "new share can recover while old capture is pending")
        expect(!requests.finish(oldRequest) && requests.activeID == newRequest, "old task completion cannot clear new capture")
        expect(requests.finish(newRequest) && requests.activeID == nil, "current capture completion releases its slot")
        let encoded = WireCodec.frame(data, sequence: 9, identity: one)!
        expect(WireCodec.readFrame(encoded)?.header.identity == one, "identity survives bounded binary frame")
        expect(WireCodec.readFrame(Data([0x4b, 0x46, 1]) + Data(repeating: 0, count: 20)) == nil, "legacy unidentified JPEG cannot display as synchronized")
        expect(WireCodec.readFrame(Data([0x4b, 0x46, 2, 255, 255]) + data) == nil, "oversized header rejected")
        expect(WireCodec.readFrame(encoded.prefix(8)) == nil, "truncated identity rejected")
        expect(WireCodec.readFrame(encoded + Data(repeating: 0, count: WireCodec.maxFrameBytes)) == nil, "oversized JPEG rejected after metadata")
        var invalid = one; invalid.slideIndex = nil
        expect(WireCodec.frame(data, sequence: 1, identity: invalid) == nil, "partial page identity rejected")
        let oldState = PresentationState()
        receiver = SlideFrameReceiver()
        expect(!receiver.accept(frame(one, 1), state: oldState), "state lacking identity remains unavailable")
        let command = WireMessage(kind: "control", action: .next, frameIdentity: one)
        let commandData = try JSONEncoder().encode(command)
        expect(WireCodec.decode(commandData)?.frameIdentity == one, "remote action carries displayed page identity")
    }
}
