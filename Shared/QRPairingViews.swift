import SwiftUI
#if os(macOS)
import CoreImage.CIFilterBuiltins
struct QRPairingSheet: View {
    @ObservedObject var link: PeerLink
    @Environment(\.dismiss) private var dismiss
    @State private var addresses = PairingTicket.addresses()
    @State private var address = ""
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image("BrandMascot").resizable().scaledToFit().frame(width: 40, height: 40)
                Text("iPhoneで読み取る").font(.title2.bold())
                Spacer(); Button("閉じる") { dismiss() }
            }
            if let ticket = link.pairingTicket, let image = qr(ticket.text) {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 280, height: 280).padding(16).background(.white)
                Text("同じWi-Fiにつなぎ、iPhoneで「QRでつなぐ」").font(.callout)
                Text("読み取り後、このMacで接続を許可してください").font(.caption)
                if addresses.count > 1 {
                    Picker("接続先", selection: $address) {
                        ForEach(addresses, id: \.self) { Text($0).tag($0) }
                    }.onChange(of: address) { _, value in link.selectQRAddress(value) }
                }
                Text("10分間有効 · この画面は共有しないでください").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Wi-FiにつないでQRを表示してください").padding()
            }
            Button("QRを更新") { addresses = PairingTicket.addresses(); address = addresses.first ?? ""; link.showQR(refresh: true) }
                .disabled(link.connectedName != nil || link.invitation != nil)
        }.padding(24).frame(width: 420)
            .onAppear { address = link.pairingTicket?.host ?? addresses.first ?? ""; link.showQR() }
            .alert("iPhoneからの接続", isPresented: Binding(get: { link.invitation != nil }, set: { _ in }), presenting: link.invitation) { invitation in
                Button("許可") { link.respondToInvitation(accept: true, invitationID: invitation.id) }
                Button("拒否", role: .cancel) { link.respondToInvitation(accept: false, invitationID: invitation.id) }
            } message: { invitation in Text("\(invitation.name) にスライドと原稿を共有します。") }
            .onChange(of: link.connectedName) { _, value in if value != nil { dismiss() } }
    }
    private func qr(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}
#else
import VisionKit
import AVFoundation
struct QRScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allowed = false
    @State private var message = "カメラの許可を確認中"
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if allowed && DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner { text in
                        guard PairingTicket.parse(text) != nil else { message = "MacでQRを更新して読み取ってください"; return }
                        dismiss(); onCode(text)
                    }.clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 70))
                    Text("カメラが使えない場合は、近くのMacから接続してください")
                }
                Text(message).font(.callout)
            }.padding().navigationTitle("MacのQRを読み取る")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
                .task {
                    allowed = await AVCaptureDevice.requestAccess(for: .video)
                    message = allowed ? "Macと同じWi-Fiにつないでください" : "設定でカメラへのアクセスを許可してください"
                }
        }
    }
}
private struct QRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let view = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        view.delegate = context.coordinator
        try? view.startScanning()
        return view
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) { uiViewController.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var delivered = false
        init(_ onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    if PairingTicket.parse(text) != nil { delivered = true; dataScanner.stopScanning() }
                    onCode(text)
                }
            }
        }
    }
}
#endif
