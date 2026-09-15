import Foundation
import Network
import Security
import Darwin

/// A short-lived capability shown only on the host screen. Never log or persist it.
struct PairingTicket: Codable, Equatable {
    let version: Int
    let host: String
    let port: UInt16
    let key: Data
    let name: String
    let expires: Date
    var text: String { "kanpeki://pair/" + ((try? JSONEncoder().encode(self)) ?? Data()).base64EncodedString() }
    static func parse(_ text: String, now: Date = Date()) -> PairingTicket? {
        let prefix = "kanpeki://pair/"
        guard text.hasPrefix(prefix), text.utf8.count < 4096,
              let bytes = Data(base64Encoded: String(text.dropFirst(prefix.count))),
              let ticket = try? JSONDecoder().decode(Self.self, from: bytes),
              ticket.version == 1, ticket.port > 0, ticket.key.count == 32,
              !ticket.name.isEmpty, ticket.name.utf8.count <= 160,
              ticket.expires > now, ticket.expires.timeIntervalSince(now) <= 610,
              validLocalIPv4(ticket.host) else { return nil }
        return ticket
    }
    static func safeDisplayName(_ value: String) -> String {
        var text = String(value.prefix(40))
        while text.utf8.count > 63 { text.removeLast() }
        return text.isEmpty ? "Kanpeki" : text
    }
    static func validLocalIPv4(_ address: String) -> Bool {
        let p = address.split(separator: ".", omittingEmptySubsequences: false)
        guard p.count == 4, p.allSatisfy({ UInt8($0) != nil && String(UInt8($0)!) == $0 }) else { return false }
        let n = p.map { Int($0)! }
        return n[0] == 10 || (n[0] == 172 && (16...31).contains(n[1])) ||
            (n[0] == 192 && n[1] == 168) || (n[0] == 169 && n[1] == 254)
    }
    static func addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var result: [(String, String)] = []
        var cursor = head
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let addr = item.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  item.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let iface = String(cString: item.pointee.ifa_name)
            guard iface.hasPrefix("en") || iface.hasPrefix("bridge") else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: buffer)
                if validLocalIPv4(ip) { result.append((iface, ip)) }
            }
        }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

/// Length-delimited TLS-PSK stream. Main-queue confinement and identity checks reject old callbacks.
/// TLS authenticates the QR capability; application approval still happens in PeerLink.
final class DirectPairing {
    static let maxPacket = 512 * 1024
    var onTicket: ((PairingTicket?) -> Void)?
    var onReady: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onEnd: ((String) -> Void)?
    private var listener: NWListener?
    private var connection: NWConnection?
    private var expiry: DispatchWorkItem?
    private var timer: DispatchWorkItem?
    private var buffer = Data()
    private var queuedBytes = 0
    private var key = Data()
    private var expires = Date.distantPast
    private var hostName = "Mac"
    private var selectedAddress: String?

    static func parameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let identity = Data("kanpeki-qr-v1".utf8)
        key.withUnsafeBytes { k in identity.withUnsafeBytes { i in
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                DispatchData(bytes: k) as __DispatchData, DispatchData(bytes: i) as __DispatchData)
        }}
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        return NWParameters(tls: tls, tcp: tcp)
    }

    func listen(name: String, address: String? = nil) {
        stop()
        hostName = name; selectedAddress = address
        key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { onEnd?("QRを作成できませんでした"); return }
        expires = Date().addingTimeInterval(600)
        do {
            let server = try NWListener(using: Self.parameters(key: key), on: .any)
            listener = server
            server.stateUpdateHandler = { [weak self, weak server] state in
                guard let self, let server, self.listener === server else { return }
                if case .ready = state { self.publishTicket() }
                if case .failed = state { self.stop(); self.onEnd?("QR接続を開始できませんでした") }
            }
            server.newConnectionHandler = { [weak self, weak server] conn in
                guard let self, let server, self.listener === server, self.connection == nil, self.expires > Date() else { conn.cancel(); return }
                self.attach(conn)
            }
            server.start(queue: .main)
            let work = DispatchWorkItem { [weak self, weak server] in
                guard let self, self.listener === server else { return }
                self.listener?.cancel(); self.listener = nil; self.onTicket?(nil)
                // Existing approved sessions may continue after the pairing code expires.
            }
            expiry = work; DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: work)
        } catch { onEnd?("QR接続を開始できませんでした") }
    }
    func selectAddress(_ address: String) { selectedAddress = address; publishTicket() }
    private func publishTicket() {
        guard let port = listener?.port, let ip = selectedAddress ?? PairingTicket.addresses().first else { onTicket?(nil); return }
        onTicket?(PairingTicket(version: 1, host: ip, port: port.rawValue, key: key, name: hostName, expires: expires))
    }
    func connect(_ ticket: PairingTicket) {
        stop()
        guard PairingTicket.parse(ticket.text) != nil else { onEnd?("QRの期限が切れています。Macで更新してください"); return }
        attach(NWConnection(host: NWEndpoint.Host(ticket.host), port: NWEndpoint.Port(rawValue: ticket.port)!, using: Self.parameters(key: ticket.key)))
    }
    private func attach(_ conn: NWConnection) {
        connection = conn; buffer.removeAll(); queuedBytes = 0
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, self.connection === conn else { return }
            switch state {
            case .ready: self.onReady?(); self.receive(conn)
            case .failed, .cancelled: self.finish(conn, "接続できませんでした。同じWi-Fi・Macの許可を確認してください")
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self, weak conn] in
            guard let self, let conn, self.connection === conn else { return }
            self.finish(conn, "接続がタイムアウトしました。同じWi-Fiを確認してください")
        }
        timer = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        conn.start(queue: .main)
    }
    func send(_ data: Data) {
        guard let conn = connection, !data.isEmpty, data.count <= Self.maxPacket else { return }
        guard queuedBytes + data.count <= Self.maxPacket * 2 else { finish(conn, "通信が混雑しています。再接続してください"); return }
        var size = UInt32(data.count).bigEndian
        var packet = withUnsafeBytes(of: &size) { Data($0) }; packet.append(data)
        queuedBytes += data.count
        conn.send(content: packet, completion: .contentProcessed { [weak self, weak conn] error in
            guard let self, let conn, self.connection === conn else { return }
            self.queuedBytes -= data.count
            if error != nil { self.finish(conn, "通信が切断されました") }
        })
    }
    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, complete, error in
            guard let self, let conn, self.connection === conn else { return }
            if let data { self.buffer.append(data) }
            while self.buffer.count >= 4 {
                let size = self.buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                guard size > 0, size <= Self.maxPacket else { self.finish(conn, "通信形式が正しくありません"); return }
                guard self.buffer.count >= size + 4 else { break }
                let packet = Data(self.buffer.dropFirst(4).prefix(size))
                self.buffer.removeFirst(size + 4)
                self.timer?.cancel()
                self.onData?(packet)
                guard self.connection === conn else { return }
            }
            if error != nil || complete { self.finish(conn, "接続が切断されました") }
            else { self.receive(conn) }
        }
    }
    private func finish(_ conn: NWConnection, _ message: String) {
        guard connection === conn else { return }
        connection = nil; timer?.cancel(); conn.cancel(); buffer.removeAll(); queuedBytes = 0
        onEnd?(message)
    }
    func stop() {
        expiry?.cancel(); timer?.cancel()
        listener?.cancel(); listener = nil
        let old = connection; connection = nil; old?.cancel()
        buffer.removeAll(); queuedBytes = 0; onTicket?(nil)
    }
}
