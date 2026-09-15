import Foundation
import Combine
import MultipeerConnectivity
#if os(iOS)
import UIKit
#endif

struct PeerInvitation {
    let id: UUID
    let name: String
}

/// One explicitly accepted phone per Mac. At most one JPEG waits for a receiver ACK.
final class PeerLink: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    static let service = "kanpeki-v1"
    @Published var status = "未接続"
    @Published var availablePeers: [MCPeerID] = []
    @Published var incompatiblePeers: [MCPeerID] = []
    @Published var pairingTicket: PairingTicket?
    private let direct = DirectPairing()
    private var directOperation: UUID?
    private var directApproved = false
    private var directName: String?
    private var directHelloReceived = false
    private var resumeAfterForeground = false
    @Published var connectedName: String? = nil
    @Published private(set) var invitation: PeerInvitation?
    @Published var running = false
    var onMessage: ((WireMessage) -> Void)?
    var onFrame: ((SlideFramePacket) -> Void)?
    var onConnection: ((Bool) -> Void)?
    let isHost: Bool
    private let localPeer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var pendingInvitation: (id: UUID, respond: (Bool, MCSession?) -> Void)?
    private var lastFrame: UInt64 = 0
    private var sentFrame: UInt64 = 0
    private var pendingFrame: UInt64?
    private var approval = PeerApprovalState<MCPeerID>()
    private let callbacks = PeerCallbackGate<MCPeerID>()

    init(isHost: Bool) {
        self.isHost = isHost
        #if os(macOS)
        let label = Host.current().localizedName ?? "Kanpeki Mac"
        #else
        let label = UIDevice.current.name
        #endif
        localPeer = MCPeerID(displayName: PairingTicket.safeDisplayName(label))
        super.init()
        renewSession()
        direct.onTicket = { [weak self] in self?.pairingTicket = $0 }
        direct.onReady = { [weak self] in
            guard let self else { return }
            if !self.isHost { self.direct.send(Data(("hello:" + self.localPeer.displayName).utf8)) }
        }
        direct.onData = { [weak self] in self?.receiveDirect($0) }
        direct.onEnd = { [weak self] message in
            guard let self else { return }
            let used = self.directOperation != nil || self.directApproved
            self.clearDirect()
            if used { self.connectedName = nil; self.onConnection?(false); self.status = message }
        }
    }

    func suspend() { resumeAfterForeground = running; stop() }
    func resume() { if resumeAfterForeground { resumeAfterForeground = false; start() } }
    func selectQRAddress(_ address: String) { direct.selectAddress(address) }
    func showQR(refresh: Bool = false) {
        guard isHost, connectedName == nil, approval.operationID == nil, directOperation == nil else { return }
        if !running { start() }
        direct.listen(name: localPeer.displayName, refresh: refresh)
    }
    func connectQR(_ text: String) {
        guard !isHost else { return }
        guard let ticket = PairingTicket.parse(text) else { status = "カンペきの有効なQRを読み取ってください"; return }
        stop(); start()
        let operation = UUID()
        directOperation = operation; directName = ticket.name; directHelloReceived = false
        status = "QRで接続中 · Mac側で許可してください"
        direct.connect(ticket)
        expireDirect(operation)
    }
    private func expireDirect(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.directOperation == id, !self.directApproved else { return }
            self.clearDirect(); self.status = "接続できませんでした。QRを更新して再試行してください"
        }
    }
    private func clearDirect() {
        if invitation?.id == directOperation { invitation = nil }
        directOperation = nil; directApproved = false; directHelloReceived = false; directName = nil
        direct.stop(); pendingFrame = nil; lastFrame = 0; sentFrame = 0
    }
    private func receiveDirect(_ data: Data) {
        guard running else { return }
        if !directApproved {
            if isHost {
                guard approval.operationID == nil, connectedName == nil, !directHelloReceived,
                      data.count <= 200, let text = String(data: data, encoding: .utf8), text.hasPrefix("hello:"), text.count > 6 else { clearDirect(); return }
                directHelloReceived = true; directOperation = UUID(); directName = String(text.dropFirst(6).prefix(40))
                invitation = PeerInvitation(id: directOperation!, name: directName!)
                expireDirect(directOperation!)
            } else if directOperation != nil && data == Data("accepted".utf8) {
                directApproved = true; connectedName = directName
                status = "QRで接続中 · \(directName ?? "Mac")"; onConnection?(true)
            } else { clearDirect(); status = "Mac側で接続が許可されませんでした" }
            return
        }
        if let frame = WireCodec.readFrame(data), !isHost {
            send(WireMessage(kind: "frameAck", frameSequence: frame.header.sequence))
            guard frame.header.sequence > lastFrame else { return }
            lastFrame = frame.header.sequence; onFrame?(frame)
        } else if let message = WireCodec.decode(data) {
            if message.kind == "frameAck", isHost {
                if message.frameSequence == pendingFrame { pendingFrame = nil }
            } else { onMessage?(message) }
        }
    }

    /// Each admission gets a new transport object: even a same-peer retry has no old callbacks.
    private func renewSession(peer: MCPeerID? = nil) {
        let previous = session
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        callbacks.begin(source: session!, peer: peer)
        session.delegate = self
        previous?.delegate = nil
        previous?.disconnect()
        lastFrame = 0; sentFrame = 0; pendingFrame = nil
    }

    func start() {
        guard !running else { return }
        running = true
        approval.start()
        renewSession()
        if isHost {
            advertiser = MCNearbyServiceAdvertiser(peer: localPeer, discoveryInfo: ["role": "mac", "version": "2"], serviceType: Self.service)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
            status = "iPhoneからの接続待機中"
        } else {
            browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.service)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
            status = "近くのMacを検索中"
        }
    }

    func stop() {
        running = false
        clearDirect()
        approval.stop()
        rejectPendingInvitation()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser?.delegate = nil; advertiser = nil
        browser?.delegate = nil; browser = nil
        renewSession()
        availablePeers = []; incompatiblePeers = []
        connectedName = nil
        status = "停止"
        onConnection?(false)
    }

    func invite(_ peer: MCPeerID) {
        guard running, !isHost, directOperation == nil, let browser, availablePeers.contains(peer),
              let operation = approval.begin(peer: peer, needsApproval: false) else { return }
        direct.stop()
        renewSession(peer: peer)
        status = "Mac側で接続を許可してください"
        browser.invitePeer(peer, to: session, withContext: Data("kanpeki-v2".utf8), timeout: 20)
        expireInvitation(operation)
    }

    private func expireInvitation(_ operation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 21) { [weak self] in
            guard let self, self.running, self.approval.cancel(operationID: operation) else { return }
            self.rejectPendingInvitation()
            self.renewSession()
            self.status = "接続できませんでした。Macの許可とネットワークを確認してください"
        }
    }

    private func rejectPendingInvitation() {
        let pending = pendingInvitation
        pendingInvitation = nil
        invitation = nil
        pending?.respond(false, nil)
    }

    func respondToInvitation(accept: Bool, invitationID: UUID) {
        if let operation = directOperation, operation == invitationID, isHost, running {
            invitation = nil
            guard accept else { clearDirect(); status = "接続を見送りました。QRを更新できます"; return }
            directApproved = true; connectedName = directName
            direct.send(Data("accepted".utf8))
            status = "QRで接続中 · \(directName ?? "iPhone")"; onConnection?(true)
            return
        }
        guard running, let pending = pendingInvitation, pending.id == invitationID else { return }
        if accept {
            guard approval.approve(operationID: invitationID) else { return }
            pendingInvitation = nil; invitation = nil
            status = "接続処理中"
            pending.respond(true, session)
        } else {
            guard approval.cancel(operationID: invitationID) else { return }
            rejectPendingInvitation()
            renewSession()
            status = "iPhoneからの接続待機中"
        }
    }

    private var approvedPeer: MCPeerID? {
        guard running, let peer = approval.peer, approval.allowsTraffic(from: peer),
              session.connectedPeers.contains(peer) else { return nil }
        return peer
    }

    func send(_ message: WireMessage, reliably: Bool = true) {
        guard let data = try? JSONEncoder().encode(message), data.count <= WireCodec.maxMessageBytes else { return }
        if directApproved { direct.send(data); return }
        guard let peer = approvedPeer else { return }
        do { try session.send(data, toPeers: [peer], with: reliably ? .reliable : .unreliable) }
        catch { status = "送信失敗: \(error.localizedDescription)" }
    }

    func sendFrame(_ jpeg: Data, identity: SlideFrameIdentity) {
        guard pendingFrame == nil, directApproved || approvedPeer != nil else { return }
        sentFrame &+= 1
        guard let data = WireCodec.frame(jpeg, sequence: sentFrame, identity: identity) else { return }
        if directApproved { pendingFrame = sentFrame; direct.send(data); return }
        guard let peer = approvedPeer else { return }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            pendingFrame = sentFrame
        } catch { status = "画像送信失敗: \(error.localizedDescription)" }
    }

    private func acknowledgeFrame(_ sequence: UInt64, from peer: MCPeerID) {
        guard running, approval.allowsFrameAcknowledgement(from: peer),
              session.connectedPeers.contains(peer),
              let data = try? JSONEncoder().encode(WireMessage(kind: "frameAck", frameSequence: sequence)) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let ending = state == .notConnected
        guard let epoch = callbacks.ticket(source: session, peer: peerID, ending: ending) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session === session,
                  self.callbacks.accepts(epoch, source: session, ended: ending),
                  let operation = self.approval.operationID else { return }
            switch state {
            case .connected:
                guard self.approval.connected(peer: peerID, operationID: operation) else { return }
                self.connectedName = peerID.displayName
                self.lastFrame = 0
                self.sentFrame = 0
                self.pendingFrame = nil
                self.status = "接続中 · \(peerID.displayName)"
                self.onConnection?(true)
            case .notConnected:
                guard self.approval.disconnected(peer: peerID, operationID: operation) else { return }
                self.connectedName = nil
                self.rejectPendingInvitation()
                self.renewSession()
                self.status = self.running ? "切断されました。再接続してください" : "停止"
                self.onConnection?(false)
            case .connecting:
                if self.approval.phase == .connecting { self.status = "接続処理中" }
            @unknown default: break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard session.connectedPeers.contains(peerID) else { return }
        guard let epoch = callbacks.ticket(source: session, peer: peerID) else { return }
        if let frame = WireCodec.readFrame(data), !isHost {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session === session, self.callbacks.accepts(epoch, source: session),
                      self.running, self.approval.allowsFrameAcknowledgement(from: peerID) else { return }
                // ACK even discarded/duplicate frames so one stale packet cannot stall the bounded sender.
                self.acknowledgeFrame(frame.header.sequence, from: peerID)
                guard self.approvedPeer == peerID else { return }
                guard frame.header.sequence > self.lastFrame else { return }
                self.lastFrame = frame.header.sequence
                self.onFrame?(frame)
            }
        } else if let message = WireCodec.decode(data) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session === session, self.callbacks.accepts(epoch, source: session),
                      self.approvedPeer == peerID else { return }
                if message.kind == "frameAck", self.isHost {
                    if message.frameSequence == self.pendingFrame { self.pendingFrame = nil }
                } else { self.onMessage?(message) }
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.isHost, self.directOperation == nil, self.advertiser === advertiser,
                  context == Data("kanpeki-v2".utf8),
                  let operation = self.approval.begin(peer: peerID, needsApproval: true) else {
                invitationHandler(false, nil); return
            }
            self.direct.stop()
            self.renewSession(peer: peerID)
            self.pendingInvitation = (operation, invitationHandler)
            self.invitation = PeerInvitation(id: operation, name: peerID.displayName)
            self.expireInvitation(operation)
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            guard self.running, self.advertiser === advertiser else { return }
            self.advertiser?.stopAdvertisingPeer(); self.advertiser = nil
            if self.directOperation == nil { self.status = "近隣検索の待機に失敗しました。QR接続を試してください" }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["role"] == "mac" else { return }
        let compatible = info?["version"] == "2"
        DispatchQueue.main.async {
            guard self.running, self.browser === browser else { return }
            if compatible {
                if !self.availablePeers.contains(peerID) { self.availablePeers.append(peerID) }
                self.availablePeers.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            } else if !self.incompatiblePeers.contains(peerID) { self.incompatiblePeers.append(peerID) }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            guard self.running, self.browser === browser else { return }
            self.availablePeers.removeAll { $0 == peerID }; self.incompatiblePeers.removeAll { $0 == peerID }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            guard self.running, self.browser === browser else { return }
            self.browser?.stopBrowsingForPeers(); self.browser = nil
            if self.directOperation == nil { self.status = "近隣検索に失敗しました。再検索またはQR接続を試してください" }
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
