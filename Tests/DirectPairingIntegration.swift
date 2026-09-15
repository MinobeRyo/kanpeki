import Foundation
import Network
/// Explicit local-network integration check; run separately from offline core checks.
@main struct DirectPairingIntegration {
    static func main() {
        let host = DirectPairing(), phone = DirectPairing()
        let wrongKey = CommandLine.arguments.contains("--wrong-key")
        var started = false, received = 0
        let packets = [Data("hello".utf8), Data(repeating: 65, count: 180 * 1024), Data("end".utf8)]
        host.onTicket = { ticket in
            guard let ticket, !started else { return }; started = true
            phone.connect(PairingTicket(version: 1, host: ticket.host, port: ticket.port,
                key: wrongKey ? Data(repeating: 0, count: 32) : ticket.key, name: ticket.name, expires: ticket.expires))
        }
        host.onData = { data in
            precondition(!wrongKey, "Wrong key must not deliver data")
            host.send(data)
        }
        phone.onReady = {
            precondition(!wrongKey, "Wrong key must not complete TLS")
            packets.forEach { phone.send($0) }
        }
        phone.onData = { data in
            precondition(data == packets[received], "Framing/order corrupted")
            received += 1
            if received == packets.count { host.stop(); phone.stop(); print("TLS-PSK ordered frame roundtrip passed"); exit(0) }
        }
        phone.onEnd = { _ in
            if wrongKey { print("Wrong TLS key rejected"); exit(0) }
            print("Connection failed"); exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) { print("Integration timeout"); exit(1) }
        host.listen(name: "Local integration test")
        dispatchMain()
    }
}
