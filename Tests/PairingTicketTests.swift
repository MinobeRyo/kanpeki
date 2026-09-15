import Foundation
@main struct PairingTicketTests {
    static func main() {
        let now = Date()
        func ticket(host: String = "192.168.1.2", port: UInt16 = 1234, key: Data = Data(repeating: 1, count: 32), version: Int = 1, ttl: Double = 300) -> PairingTicket {
            PairingTicket(version: version, host: host, port: port, key: key, name: "学生のMac", expires: now.addingTimeInterval(ttl))
        }
        let stable = ticket()
        let firstText = stable.text
        for _ in 0..<1000 {
            precondition(stable.text == firstText, "Unchanged QR must have identical bytes on redraw")
            precondition(PairingTicket.parse(firstText, now: now)?.text == firstText)
        }
        precondition(PairingTicket.parse(ticket().text, now: now) == ticket())
        for ip in ["10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.0.2", "169.254.1.2"] {
            precondition(PairingTicket.parse(ticket(host: ip).text, now: now) != nil)
        }
        for ip in ["8.8.8.8", "127.0.0.1", "0.0.0.0", "224.0.0.1", "172.32.0.1", "192.168.1.256", "192.168.01.2", "localhost", "example.com", "10.1.2", "10.1.2.3:90"] {
            precondition(PairingTicket.parse(ticket(host: ip).text, now: now) == nil)
        }
        for text in ["https://example.com", "kanpeki://pair/bad", String(repeating: "x", count: 5000),
                     ticket(port: 0).text, ticket(key: Data()).text, ticket(version: 2).text,
                     ticket(ttl: 0).text, ticket(ttl: -1).text, ticket(ttl: 611).text] {
            precondition(PairingTicket.parse(text, now: now) == nil)
        }
        precondition(PairingTicket.safeDisplayName(String(repeating: "学", count: 40)).utf8.count <= 63)
        precondition(PairingTicket.safeDisplayName(String(repeating: "👩‍💻", count: 40)).utf8.count <= 63)
        precondition(!PairingTicket.safeDisplayName("").isEmpty)
        print("Pairing ticket: 29 validation checks and 1000 stable QR roundtrips passed")
    }
}
