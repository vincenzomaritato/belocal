import SwiftUI

struct AuthBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .secondarySystemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.blue.opacity(0.09))
                .frame(width: 320, height: 320)
                .blur(radius: 42)
                .offset(x: 120, y: -130)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.teal.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 44)
                .offset(x: -120, y: 140)
        }
        .overlay {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.35))
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
