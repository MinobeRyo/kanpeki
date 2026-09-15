import Foundation
import Combine
@main struct QRPeerIntegration {
    static func main() {
        let host = PeerLink(isHost: true), phone = PeerLink(isHost: false)
        var subscriptions = Set<AnyCancellable>()
        var requested = false, approved = false, sawInvitation = false
        let rejecting = CommandLine.arguments.contains("--reject")
        host.$pairingTicket.compactMap { $0 }.sink { ticket in
            guard !requested else { return }; requested = true; print("ticket issued")
            phone.connectQR(ticket.text)
        }.store(in: &subscriptions)
        host.$invitation.compactMap { $0 }.sink { invitation in
            sawInvitation = true; print("invitation received")
            // Publishing occurs before the value is assigned; act on the next main turn.
            DispatchQueue.main.async {
                precondition(host.connectedName == nil && phone.connectedName == nil)
                host.respondToInvitation(accept: !rejecting, invitationID: invitation.id)
                approved = !rejecting
            }
        }.store(in: &subscriptions)
        host.onMessage = { message in
            print("host message")
            precondition(approved, "Data before host approval")
            precondition(message.kind == "control" && message.action == .refresh)
            host.send(WireMessage(kind: "state", state: PresentationState()))
        }
        phone.onConnection = { connected in
            print("phone connected", connected)
            if connected {
                precondition(approved)
                phone.send(WireMessage(kind: "control", action: .refresh))
            } else if sawInvitation && rejecting {
                print("QR rejection closes session"); exit(0)
            }
        }
        phone.onMessage = { message in
            print("phone message")
            precondition(message.kind == "state" && message.state != nil)
            phone.stop(); host.stop()
            precondition(phone.connectedName == nil && host.connectedName == nil && host.pairingTicket == nil)
            print("QR explicit approval, wire roundtrip and stop passed"); exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("QR peer timeout"); exit(1) }
        host.showQR()
        withExtendedLifetime(subscriptions) { dispatchMain() }
    }
}
