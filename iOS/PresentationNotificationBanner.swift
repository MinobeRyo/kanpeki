import SwiftUI
import UIKit

/// Own at the presentation/model level, not inside a conditional expired-only view.
@MainActor
final class PresentationNotificationPresenter: ObservableObject {
    private var policy = PresentationNotificationPolicy()
    private let vibrate: () -> Void

    init(vibrate: @escaping () -> Void = {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }) {
        self.vibrate = vibrate
    }

    func update(_ input: PresentationNotificationInput) {
        if policy.consumeTimeExpiration(input) { vibrate() }
    }
}

/// A short, nonmodal status. It never covers the slide or intercepts slide gestures.
struct PresentationNotificationBanner: View {
    @ObservedObject var presenter: PresentationNotificationPresenter
    var input: PresentationNotificationInput

    var body: some View {
        Group {
            if input.showsTimeExpired {
                Label("設定時間になりました", systemImage: "clock.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 92 / 255, green: 102 / 255, blue: 115 / 255))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 249 / 255, green: 255 / 255, blue: 230 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 1, green: 87 / 255, blue: 87 / 255))
                            .frame(width: 3)
                    }
                    .accessibilityElement(children: .combine)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: input, initial: true) { _, value in presenter.update(value) }
    }
}
