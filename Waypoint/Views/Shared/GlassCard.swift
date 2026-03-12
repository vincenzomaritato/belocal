import SwiftUI
import UIKit

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
    }
}

#Preview {
    GlassCard {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Glass Card"))
                .font(.headline)
            Text(L10n.tr("Reusable container with material blur and subtle stroke."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .background(
        LinearGradient(
            colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
