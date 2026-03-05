import SwiftUI

enum SyncBannerKind: Equatable {
    case queued(count: Int)
    case syncing(count: Int)
    case synced
    case failed(count: Int)
    case offline

    var iconName: String {
        switch self {
        case .queued:
            return "clock.badge.exclamationmark"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "wifi.slash"
        }
    }

    var title: String {
        switch self {
        case .queued(let count):
            return count == 1 ? "1 change in queue" : "\(count) changes in queue"
        case .syncing(let count):
            return count == 1 ? "Syncing 1 change" : "Syncing \(count) changes"
        case .synced:
            return "All changes synced"
        case .failed(let count):
            return count == 1 ? "1 sync error" : "\(count) sync errors"
        case .offline:
            return "Offline mode enabled"
        }
    }

    var tint: Color {
        switch self {
        case .queued:
            return .orange
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .failed:
            return .red
        case .offline:
            return .indigo
        }
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    let primaryActionTitle: String
    let primaryAction: () -> Void
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

struct ActionableErrorCard: View {
    let title: String
    let message: String
    let retryAction: () -> Void
    let offlineAction: () -> Void
    let supportAction: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Try Again", action: retryAction)
                        .buttonStyle(.borderedProminent)

                    Button("Work Offline", action: offlineAction)
                        .buttonStyle(.bordered)

                    Button("Contact Support", action: supportAction)
                        .buttonStyle(.bordered)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

struct SyncStatusBanner: View {
    let kind: SyncBannerKind
    var primaryActionTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: kind.iconName)
                    .foregroundStyle(kind.tint)
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            if let primaryActionTitle, let primaryAction {
                HStack(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(kind.tint.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }
}

enum SupportContact {
    static func emailURL(subject: String, body: String) -> URL? {
        let escapedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let escapedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:support@apollo.com?subject=\(escapedSubject)&body=\(escapedBody)")
    }
}
