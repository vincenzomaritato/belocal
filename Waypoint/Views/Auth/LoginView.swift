import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AppBootstrap.self) private var bootstrap

    let onSignedIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = true
    @State private var isSigningIn = false
    @State private var showPassword = false
    @State private var validationMessage: String?
    @State private var mode: AuthMode = .signIn

    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn
        case register

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign in"
            case .register: return "Create account"
            }
        }

        var headline: String {
            switch self {
            case .signIn: return "Welcome back"
            case .register: return "Create your account"
            }
        }

        var subtitle: String {
            switch self {
            case .signIn:
                return "Access your trips, plans, and profile in one place."
            case .register:
                return "Set up a new account and complete your onboarding flow."
            }
        }

        var cta: String {
            switch self {
            case .signIn: return "Sign in"
            case .register: return "Create account"
            }
        }
    }

    private var isFormValid: Bool {
        email.contains("@") && password.count >= 8
    }

    var body: some View {
        ZStack {
            AuthBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    authCard
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.top, 42)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(.blue)
        .onSubmit {
            if focusedField == .email {
                focusedField = .password
            } else {
                attemptSignIn()
            }
        }
        .onAppear {
            if email.isEmpty {
                email = bootstrap.settingsStore.authenticatedEmail
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                    Image(systemName: "airplane.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Waypoint")
                        .font(.title2.weight(.bold))
                    Text("Travel Intelligence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Plan better journeys with the clarity of Apple-native design.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $mode) {
                ForEach(AuthMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text(mode.headline)
                    .font(.title2.weight(.semibold))
                Text(mode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                AuthField(
                    title: "Email",
                    icon: "envelope",
                    text: $email,
                    prompt: "name@company.com",
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )
                .focused($focusedField, equals: .email)

                passwordField
                    .focused($focusedField, equals: .password)
            }

            HStack {
                Toggle("Remember me", isOn: $rememberMe)
                    .toggleStyle(.switch)
                    .font(.footnote)

                Spacer()

                Button("Forgot password?") {}
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Button {
                attemptSignIn()
            } label: {
                HStack(spacing: 10) {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(isSigningIn ? "Processing..." : mode.cta)
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn || !isFormValid)

            #if DEBUG
            Button {
                let now = Date()
                let debugSession = SupabaseSession(
                    accessToken: "debug-access-token",
                    refreshToken: "debug-refresh-token",
                    expiresAt: now.addingTimeInterval(24 * 60 * 60),
                    userID: UUID().uuidString,
                    email: "test@waypoint.local"
                )
                bootstrap.settingsStore.completeSupabaseSignIn(session: debugSession, rememberEmail: true)
                onSignedIn()
            } label: {
                Label("Skip sign-in (TEST)", systemImage: "wand.and.stars")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            #endif
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 10)
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Group {
                if showPassword {
                    TextField("At least 8 characters", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("At least 8 characters", text: $password)
                }
            }
            .textContentType(.password)

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            .accessibilityHint("Toggles secure text entry for the password field")
        }
        .font(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func attemptSignIn() {
        validationMessage = nil

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@") else {
            validationMessage = "Enter a valid email address."
            focusedField = .email
            return
        }

        guard password.count >= 8 else {
            validationMessage = "Password must be at least 8 characters."
            focusedField = .password
            return
        }

        isSigningIn = true

        Task { @MainActor in
            defer {
                isSigningIn = false
            }

            do {
                let session: SupabaseSession
                if mode == .register {
                    session = try await bootstrap.supabaseAuthService.signUp(email: normalizedEmail, password: password)
                    bootstrap.settingsStore.completeSupabaseRegistration(session: session, rememberEmail: rememberMe)
                } else {
                    session = try await bootstrap.supabaseAuthService.signIn(email: normalizedEmail, password: password)
                    bootstrap.settingsStore.completeSupabaseSignIn(session: session, rememberEmail: rememberMe)
                }
                onSignedIn()
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }
}

private struct AuthField: View {
    let title: String
    let icon: String
    @Binding var text: String
    let prompt: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                TextField(prompt, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(textContentType)
            }
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

#Preview {
    LoginView(onSignedIn: {})
        .environment(AppBootstrap())
}
