import Foundation
import Network
/// Explicit local-network integration check; run separately from offline core checks.
@main struct DirectPairingIntegration {
    static func main() {
        let host = DirectPairing(), phone = DirectPairing()
        let wrongKey = CommandLine.arguments.contains("--wrong-key")
        var started = false, received = 0
        let refresh = CommandLine.arguments.contains("--refresh")
        let lifecycle = CommandLine.arguments.contains("--lifecycle")
        var original: PairingTicket?
        var ticketEvents = 0
        let packets = [Data("hello".utf8), Data(repeating: 65, count: 180 * 1024), Data("end".utf8)]
        host.onTicket = { ticket in
            ticketEvents += 1
            guard let ticket, !started else { return }
            if refresh, original == nil {
                original = ticket
                DispatchQueue.main.async { host.listen(name: "Local integration test", refresh: true) }
                return
            }
            if let original {
                precondition(ticket.key != original.key, "Explicit refresh must rotate capability")
            }
            started = true
            let events = ticketEvents
            for _ in 0..<10 { host.listen(name: "Local integration test") }
            precondition(ticketEvents == events, "Reappearance must not publish a new ticket")
            if lifecycle {
                host.stop()
                print("QR listener reappearance stable; explicit refresh rotates key when requested")
                exit(0)
            }
            phone.connect(PairingTicket(version: 1, host: ticket.host, port: ticket.port,
                key: wrongKey ? Data(repeating: 0, count: 32) : ticket.key, name: ticket.name, expires: ticket.expires))
        }
        host.onData = { data in
            precondition(!wrongKey, "Wrong key must not deliver data")
            host.send(data)
        }
        phone.onReady = {
            precondition(!wrongKey, "Wrong key must not complete TLS")
            // Reopening the host QR while the TLS connection exists must preserve it.
            host.listen(name: "Local integration test")
            packets.forEach { phone.send($0) }
        }
        phone.onData = { data in
            precondition(data == packets[received], "Framing/order corrupted")
            received += 1
            if received == packets.count { host.stop(); phone.stop(); print("TLS-PSK ordered frame roundtrip passed"); exit(0) }
        }
        phone.onEnd = { message in
            if wrongKey { print("Wrong TLS key rejected"); exit(0) }
            print("Connection failed: \(message)"); exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) { print("Integration timeout"); exit(1) }
        host.listen(name: "Local integration test")
        dispatchMain()
    }
}
