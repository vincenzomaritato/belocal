import SwiftUI
import UIKit

struct AppLaunchIntroView: View {
    let isReturningUser: Bool

    @State private var revealContent = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 26) {
                logoBlock

                VStack(spacing: 8) {
                    Text("BeLocal")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.22, green: 0.11, blue: 0.03))

                    Text(L10n.tr("Preparing your travel space"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(red: 0.51, green: 0.30, blue: 0.13))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(revealContent ? 1 : 0)
                .offset(y: revealContent ? 0 : 8)

                loadingBar
                    .opacity(revealContent ? 1 : 0)
                    .offset(y: revealContent ? 0 : 6)
            }
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isReturningUser
                ? L10n.tr("Welcome Back") + ". " + L10n.tr("Preparing your travel space")
                : L10n.tr("Welcome to BeLocal") + ". " + L10n.tr("Preparing your travel space")
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.48)) {
                revealContent = true
            }

            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.98, blue: 0.95),
                    Color(red: 0.99, green: 0.94, blue: 0.87)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            LaunchLogoView(scale: 1.88, xOffsetRatio: 0.01, yOffsetRatio: 0.03)
                .frame(width: 420, height: 320)
                .opacity(0.06)
                .offset(x: 145, y: -180)
                .rotationEffect(.degrees(breathe ? 8 : 4))

            Circle()
                .fill(Color(red: 0.96, green: 0.45, blue: 0.02).opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 40)
                .offset(x: -40, y: -120)
                .scaleEffect(breathe ? 1.06 : 0.96)

            Ellipse()
                .fill(Color.white.opacity(0.45))
                .frame(width: 320, height: 180)
                .blur(radius: 26)
                .offset(y: 220)
        }
    }

    private var logoBlock: some View {
        LaunchLogoView(scale: 1.88, xOffsetRatio: 0.01, yOffsetRatio: 0.03)
            .frame(width: 126, height: 126)
            .scaleEffect(revealContent ? (breathe ? 1.015 : 0.985) : 0.92)
            .opacity(revealContent ? 1 : 0)
    }

    private var loadingBar: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color(red: 0.95, green: 0.88, blue: 0.77))
                .frame(width: 90, height: 6)

            Capsule(style: .continuous)
                .fill(Color(red: 0.96, green: 0.45, blue: 0.02))
                .frame(width: 42, height: 6)
                .offset(x: breathe ? 34 : 0)
        }
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
    }
}

private struct LaunchLogoView: View {
    let scale: CGFloat
    let xOffsetRatio: CGFloat
    let yOffsetRatio: CGFloat

    private static let image: UIImage? = {
        guard let url = Bundle.main.url(forResource: "logo_launch", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()

    var body: some View {
        GeometryReader { geometry in
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(
                        x: geometry.size.width * xOffsetRatio,
                        y: geometry.size.height * yOffsetRatio
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Color.clear
            }
        }
    }
}

#Preview {
    AppLaunchIntroView(isReturningUser: true)
}
