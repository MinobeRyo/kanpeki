import Foundation
import Combine
import MultipeerConnectivity
#if os(iOS)
import UIKit
#endif

/// One explicitly accepted phone per Mac. At most one JPEG waits for a receiver ACK.
final class PeerLink: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    static let service = "kanpeki-v1"
    @Published var status = "未接続"
    @Published var availablePeers: [MCPeerID] = []
    @Published var connectedName: String? = nil
    @Published var invitationName: String? = nil
    @Published var running = false
    var onMessage: ((WireMessage) -> Void)?
    var onFrame: ((Data) -> Void)?
    var onConnection: ((Bool) -> Void)?
    let isHost: Bool
    private let localPeer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var pendingInvitation: ((Bool, MCSession?) -> Void)?
    private var lastFrame: UInt64 = 0
    private var sentFrame: UInt64 = 0
    private var pendingFrame: UInt64?
    private var pendingPeer: MCPeerID?

    init(isHost: Bool) {
        self.isHost = isHost
        #if os(macOS)
        let label = Host.current().localizedName ?? "Kanpeki Mac"
        #else
        let label = UIDevice.current.name
        #endif
        localPeer = MCPeerID(displayName: String(label.prefix(40)))
        super.init()
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func start() {
        guard !running else { return }
        running = true
        if isHost {
            advertiser = MCNearbyServiceAdvertiser(peer: localPeer, discoveryInfo: ["role": "mac", "version": "1"], serviceType: Self.service)
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
        pendingInvitation?(false, nil)
        pendingInvitation = nil
        invitationName = nil
        pendingPeer = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        availablePeers = []
        connectedName = nil
        running = false
        lastFrame = 0
        sentFrame = 0
        pendingFrame = nil
        status = "停止"
    }

    func invite(_ peer: MCPeerID) {
        guard session.connectedPeers.isEmpty, pendingPeer == nil else { return }
        pendingPeer = peer
        status = "Mac側で接続を許可してください"
        browser?.invitePeer(peer, to: session, withContext: Data("kanpeki-v1".utf8), timeout: 20)
        DispatchQueue.main.asyncAfter(deadline: .now() + 21) { [weak self] in
            guard let self, self.connectedName == nil else { return }
            self.pendingPeer = nil
            self.status = "接続できませんでした。Macの許可とネットワークを確認してください"
        }
    }

    func respondToInvitation(accept: Bool) {
        let handler = pendingInvitation
        pendingInvitation = nil
        invitationName = nil
        handler?(accept, accept ? session : nil)
    }

    func send(_ message: WireMessage, reliably: Bool = true) {
        guard !session.connectedPeers.isEmpty, let data = try? JSONEncoder().encode(message), data.count <= WireCodec.maxMessageBytes else { return }
        do { try session.send(data, toPeers: session.connectedPeers, with: reliably ? .reliable : .unreliable) }
        catch { status = "送信失敗: \(error.localizedDescription)" }
    }

    func sendFrame(_ jpeg: Data) {
        guard !session.connectedPeers.isEmpty, pendingFrame == nil else { return }
        sentFrame &+= 1
        guard let data = WireCodec.frame(jpeg, sequence: sentFrame) else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            pendingFrame = sentFrame
        } catch { status = "画像送信失敗: \(error.localizedDescription)" }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.connectedName = peerID.displayName
                self.pendingPeer = nil
                self.lastFrame = 0
                self.sentFrame = 0
                self.pendingFrame = nil
                self.status = "接続中 · \(peerID.displayName)"
                self.onConnection?(true)
            case .notConnected:
                self.connectedName = nil
                self.pendingPeer = nil
                self.pendingFrame = nil
                self.status = self.running ? "切断されました。再接続してください" : "停止"
                self.onConnection?(false)
            case .connecting: self.status = "接続処理中"
            @unknown default: break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard session.connectedPeers.contains(peerID) else { return }
        if let (sequence, jpeg) = WireCodec.readFrame(data), !isHost {
            DispatchQueue.main.async { [weak self] in
                guard let self, sequence > self.lastFrame else { return }
                self.lastFrame = sequence
                self.onFrame?(jpeg)
                self.send(WireMessage(kind: "frameAck", frameSequence: sequence))
            }
        } else if let message = WireCodec.decode(data) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if message.kind == "frameAck", self.isHost {
                    if message.frameSequence == self.pendingFrame { self.pendingFrame = nil }
                } else { self.onMessage?(message) }
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session.connectedPeers.isEmpty,
                  self.pendingInvitation == nil, context == Data("kanpeki-v1".utf8) else {
                invitationHandler(false, nil); return
            }
            self.invitationName = peerID.displayName
            self.pendingInvitation = invitationHandler
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.status = "接続待機失敗: \(error.localizedDescription)"; self.running = false }
    }
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["role"] == "mac", info?["version"] == "1" else { return }
        DispatchQueue.main.async { if !self.availablePeers.contains(peerID) { self.availablePeers.append(peerID) } }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.availablePeers.removeAll { $0 == peerID } }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { self.status = "検索失敗: \(error.localizedDescription)"; self.running = false }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
