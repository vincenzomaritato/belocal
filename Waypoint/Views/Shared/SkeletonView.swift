import SwiftUI

struct SkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var highlightOpacity: Double = 0.08

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(baseColor)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(highlightColor.opacity(highlightOpacity))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.75)
            )
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    highlightOpacity = 0.16
                }
            }
            .onDisappear {
                highlightOpacity = 0.08
            }
    }

    private var baseColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var highlightColor: Color {
        colorScheme == .dark ? Color.white : Color.white
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
    }
}

#Preview {
    SkeletonView()
        .frame(height: 120)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
