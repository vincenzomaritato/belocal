import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AppBootstrap.self) private var bootstrap
    @Environment(\.colorScheme) private var colorScheme

    let onSignedIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var rememberMe = true
    @State private var passwordStoredSafely = false
    @State private var isSigningIn = false
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var notice: AuthNotice?
    @State private var mode: AuthMode = .signIn
    @State private var currentStep: AuthStep = .email
    @State private var stepDirection: StepDirection = .forward
    @State private var confirmationState: ConfirmationState?

    @FocusState private var focusedField: Field?

    enum Field {
        case email
        case password
        case confirmPassword
    }

    private enum AuthMode {
        case signIn
        case register
    }

    private enum AuthStep: Int, CaseIterable {
        case email
        case password
        case confirmation
    }

    private enum StepDirection {
        case forward
        case backward
    }

    private enum ConfirmationState {
        case inbox
    }

    private struct AuthNotice: Equatable {
        enum Kind {
            case info
            case error
        }

        let message: String
        let kind: Kind
    }

    struct PasswordRequirement: Identifiable {
        let id: String
        let title: String
        let isMet: Bool
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isEmailValid: Bool {
        let trimmed = normalizedEmail
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private var passwordRequirements: [PasswordRequirement] {
        [
            PasswordRequirement(
                id: "length",
                title: L10n.tr("Minimum 8 characters"),
                isMet: password.count >= 8
            ),
            PasswordRequirement(
                id: "number",
                title: L10n.tr("One number required"),
                isMet: password.rangeOfCharacter(from: .decimalDigits) != nil
            ),
            PasswordRequirement(
                id: "spaces",
                title: L10n.tr("No spaces allowed"),
                isMet: !password.contains(where: \.isWhitespace)
            ),
            PasswordRequirement(
                id: "symbol",
                title: L10n.tr("Add a symbol (e.g. @, #, !)"),
                isMet: password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil
            )
        ]
    }

    private var passwordMatches: Bool {
        !confirmPassword.isEmpty && confirmPassword == password
    }

    private var canProceed: Bool {
        switch currentStep {
        case .email:
            return isEmailValid
        case .password:
            switch mode {
            case .signIn:
                return password.count >= 8
            case .register:
                return passwordRequirements.allSatisfy(\.isMet) && passwordMatches && passwordStoredSafely
            }
        case .confirmation:
            return true
        }
    }

    private var sheetTitle: String {
        switch currentStep {
        case .email:
            return mode == .signIn ? L10n.tr("Welcome Back") : L10n.tr("Create Account")
        case .password:
            return mode == .signIn ? L10n.tr("Enter Password") : L10n.tr("Set Password")
        case .confirmation:
            return L10n.tr("Check Your Email")
        }
    }

    private var sheetSubtitle: String {
        switch currentStep {
        case .email:
            return mode == .signIn
                ? L10n.tr("Enter the email linked to your profile to continue.")
                : L10n.tr("Start with your email and continue into the onboarding flow.")
        case .password:
            return mode == .signIn
                ? L10n.tr("Enter your password to access saved trips, planner state, and preferences.")
                : L10n.tr("Set a strong password to keep your account safe.")
        case .confirmation:
            return L10n.f("We sent a confirmation link to %@. Open it, then sign in below.", normalizedEmail)
        }
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .email:
            return L10n.tr("Continue")
        case .password:
            return mode == .signIn ? L10n.tr("Confirm") : L10n.tr("Confirm")
        case .confirmation:
            return L10n.tr("Back to Sign In")
        }
    }

    private var accent: Color {
        .accentColor
    }

    private var accentSoft: Color {
        .accentColor.opacity(0.12)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var primaryText: Color {
        isDarkMode ? .white : .black
    }

    private var secondaryText: Color {
        isDarkMode ? Color.white.opacity(0.64) : Color.black.opacity(0.56)
    }

    private var pageGradient: [Color] {
        if isDarkMode {
            return [
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.09, green: 0.10, blue: 0.13),
                Color(red: 0.07, green: 0.10, blue: 0.13)
            ]
        }

        return [
            Color(red: 0.95, green: 0.96, blue: 0.97),
            Color(red: 0.93, green: 0.95, blue: 0.97),
            Color(red: 0.92, green: 0.95, blue: 0.97)
        ]
    }

    private var sheetBackground: Color {
        isDarkMode ? Color(red: 0.10, green: 0.11, blue: 0.14) : Color(red: 0.99, green: 0.99, blue: 0.99)
    }

    private var softFill: Color {
        isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }

    private var borderColor: Color {
        isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.14)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundLayer
                motionLayer(size: proxy.size)

                VStack(spacing: 0) {
                    Spacer(minLength: max(32, proxy.size.height * 0.06))

                    authSheet
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 10))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if email.isEmpty {
                email = bootstrap.settingsStore.authenticatedEmail
            }
            focusForCurrentStep()
        }
        .onSubmit {
            handleSubmit()
        }
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: pageGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func motionLayer(size: CGSize) -> some View {
        let factor = CGFloat(currentStep.rawValue)

        return ZStack {
            Circle()
                .fill(isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.72))
                .frame(width: size.width * 0.9, height: size.width * 0.9)
                .blur(radius: 32)
                .offset(x: 18 - (factor * 10), y: -size.height * 0.2)

            Circle()
                .fill(accent.opacity(0.1))
                .frame(width: size.width * 0.52, height: size.width * 0.52)
                .blur(radius: 30)
                .offset(x: -70 + (factor * 8), y: size.height * 0.06)

            Circle()
                .fill(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                .frame(width: size.width * 0.4, height: size.width * 0.4)
                .blur(radius: 24)
                .offset(x: 90 - (factor * 12), y: size.height * 0.18)
        }
        .animation(.easeInOut(duration: 0.45), value: currentStep.rawValue)
        .allowsHitTesting(false)
    }

    private var authSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                brandHeader
                sheetHeader

                ZStack {
                    currentStepBody
                        .id("\(mode == .signIn ? "signIn" : "register")-\(currentStep.rawValue)")
                        .transition(stepTransition)
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.9), value: currentStep.rawValue)
                .padding(.top, 20)

                if let notice {
                    noticeView(notice)
                        .padding(.top, 16)
                }

                footerArea
                    .padding(.top, 22)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var brandHeader: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("BeLocal"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(primaryText)

                    Text(mode == .signIn ? L10n.tr("Sign in to continue") : L10n.tr("Create an account to begin"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(currentStepIndexLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(softFill)
                    )
            }

            HStack(spacing: 8) {
                ForEach(AuthStep.allCases, id: \.rawValue) { step in
                    Capsule(style: .continuous)
                        .fill(step.rawValue <= currentStep.rawValue ? accent : borderColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                }
            }
        }
        .padding(.bottom, 28)
    }

    private var sheetHeader: some View {
        VStack(spacing: 14) {
            Text(sheetTitle)
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(primaryText)

            Text(sheetSubtitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
    }

    private var currentStepIndexLabel: String {
        "\(currentStep.rawValue + 1)/\(AuthStep.allCases.count)"
    }

    private var currentStepBody: some View {
        VStack(spacing: 0) {
            switch currentStep {
            case .email:
                emailStep
            case .password:
                passwordStep
            case .confirmation:
                confirmationStep
            }
        }
    }

    private var emailStep: some View {
        VStack(spacing: 18) {
            AuthEntryField(
                text: $email,
                prompt: L10n.tr("Email"),
                icon: "envelope",
                isSecure: false,
                isVisible: .constant(true),
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                focus: $focusedField,
                field: .email
            )
            .padding(.top, 26)

            Button {
                handlePrimaryAction()
            } label: {
                primaryButtonContent(enabled: canProceed)
            }
            .buttonStyle(.plain)
            .disabled(!canProceed || isSigningIn)
            .padding(.top, 8)
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 14) {
            if mode == .signIn {
                emailPill
                    .padding(.top, 22)
            } else {
                Color.clear
                    .frame(height: 20)
            }

            AuthEntryField(
                text: $password,
                prompt: mode == .signIn ? L10n.tr("Password") : L10n.tr("New Password"),
                icon: "lock",
                isSecure: true,
                isVisible: $showPassword,
                keyboardType: .default,
                textContentType: mode == .signIn ? .password : .newPassword,
                focus: $focusedField,
                field: .password
            )

            if mode == .register {
                AuthEntryField(
                    text: $confirmPassword,
                    prompt: L10n.tr("Confirm Password"),
                    icon: "lock",
                    isSecure: true,
                    isVisible: $showConfirmPassword,
                    keyboardType: .default,
                    textContentType: .newPassword,
                    focus: $focusedField,
                    field: .confirmPassword
                )

                Button {
                    passwordStoredSafely.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: passwordStoredSafely ? "checkmark.square" : "square")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(primaryText)

                        Text(L10n.tr("Password Saved Safely?"))
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(primaryText)

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .accessibilityLabel(L10n.tr("Password Saved Safely?"))
                .accessibilityValue(passwordStoredSafely ? L10n.tr("Selected") : L10n.tr("Not selected"))
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(passwordRequirements) { requirement in
                        PasswordRequirementRow(requirement: requirement)
                    }

                    PasswordRequirementRow(
                        requirement: PasswordRequirement(
                            id: "match",
                            title: L10n.tr("Passwords match"),
                            isMet: passwordMatches
                        )
                    )
                }
                .padding(.top, 8)
            } else {
                HStack {
                    Toggle(L10n.tr("Remember me"), isOn: $rememberMe)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel(L10n.tr("Remember me"))

                    Text(L10n.tr("Remember me"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button(L10n.tr("Use another email")) {
                        move(to: .email, direction: .backward)
                    }
                    .buttonStyle(.plain)
                    .accessibilityTapTarget()
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(accent)
                }
                .padding(.top, 10)
            }

            Button {
                handlePrimaryAction()
            } label: {
                primaryButtonContent(enabled: canProceed)
            }
            .buttonStyle(.plain)
            .disabled(!canProceed || isSigningIn)
            .padding(.top, 14)
        }
    }

    private var confirmationStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(softFill)
                            .frame(width: 58, height: 64)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(borderColor.opacity(0.7), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 24)

                Text(L10n.tr("Open the confirmation link from your inbox, then return here and sign in with the same password."))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
            }

            Button {
                handlePrimaryAction()
            } label: {
                primaryButtonContent(enabled: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    private var emailPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)

            Text(normalizedEmail)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(L10n.tr("Edit")) {
                move(to: .email, direction: .backward)
            }
            .buttonStyle(.plain)
            .accessibilityTapTarget()
            .font(.footnote.weight(.semibold))
            .foregroundStyle(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(accentSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var footerArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    .frame(height: 1)

                Text(L10n.tr("OR"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Rectangle()
                    .fill(isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                    .frame(height: 1)
            }
            .padding(.top, 12)

            if currentStep == .confirmation {
                Button(L10n.tr("Use another email")) {
                    confirmationState = nil
                    move(to: .email, direction: .backward)
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.medium))
                .foregroundStyle(accent)
            } else {
                HStack(spacing: 4) {
                    Text(mode == .signIn ? L10n.tr("New here?") : L10n.tr("Already have an account?"))
                        .foregroundStyle(.secondary)
                Button(mode == .signIn ? L10n.tr("Create account") : L10n.tr("Sign in")) {
                    switchMode(to: mode == .signIn ? .register : .signIn)
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .foregroundStyle(accent)
            }
                .font(.footnote.weight(.medium))
            }

        }
    }

    private func primaryButtonContent(enabled: Bool) -> some View {
        Text(isSigningIn ? L10n.tr("Processing...") : primaryButtonTitle)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(enabled ? accent : accent.opacity(0.34))
            )
            .overlay {
                if isSigningIn {
                    ProgressView()
                        .tint(.white)
                }
            }
    }

    private func noticeView(_ notice: AuthNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.kind == .error ? "exclamationmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(notice.kind == .error ? Color.red : accent)

            Text(notice.message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(notice.kind == .error ? Color.red : secondaryText)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(notice.kind == .error ? Color.red.opacity(0.08) : accentSoft)
        )
    }

    private var stepTransition: AnyTransition {
        switch stepDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private func handleSubmit() {
        switch focusedField {
        case .email:
            handlePrimaryAction()
        case .password:
            if mode == .register && confirmPassword.isEmpty {
                focusedField = .confirmPassword
            } else {
                handlePrimaryAction()
            }
        case .confirmPassword:
            handlePrimaryAction()
        case .none:
            break
        }
    }

    private func switchMode(to newMode: AuthMode) {
        guard mode != newMode else { return }

        mode = newMode
        confirmationState = nil
        notice = nil
        password = ""
        confirmPassword = ""
        passwordStoredSafely = false
        showPassword = false
        showConfirmPassword = false
        move(to: .email, direction: newMode == .register ? .forward : .backward)
    }

    private func move(to step: AuthStep, direction: StepDirection) {
        stepDirection = direction
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            currentStep = step
        }
        focusForCurrentStep()
    }

    private func focusForCurrentStep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            switch currentStep {
            case .email:
                focusedField = .email
            case .password:
                focusedField = .password
            case .confirmation:
                focusedField = nil
            }
        }
    }

    private func handlePrimaryAction() {
        notice = nil

        switch currentStep {
        case .email:
            guard validateEmail() else { return }
            move(to: .password, direction: .forward)
        case .password:
            guard validatePasswordStep() else { return }
            attemptAuthentication()
        case .confirmation:
            switchMode(to: .signIn)
            move(to: .password, direction: .forward)
        }
    }

    private func validateEmail() -> Bool {
        guard bootstrap.supabaseAuthService.config.isConfigured else {
            notice = AuthNotice(
                message: L10n.tr("Supabase is not configured. Add a valid publishable key to SupabaseConfig.plist."),
                kind: .error
            )
            return false
        }

        guard isEmailValid else {
            notice = AuthNotice(
                message: L10n.tr("Enter a valid email address."),
                kind: .error
            )
            focusedField = .email
            return false
        }

        return true
    }

    private func validatePasswordStep() -> Bool {
        switch mode {
        case .signIn:
            guard password.count >= 8 else {
                notice = AuthNotice(
                    message: L10n.tr("Password must be at least 8 characters."),
                    kind: .error
                )
                focusedField = .password
                return false
            }
        case .register:
            guard passwordRequirements.allSatisfy(\.isMet) else {
                notice = AuthNotice(
                    message: L10n.tr("Use a stronger password to continue."),
                    kind: .error
                )
                focusedField = .password
                return false
            }

            guard passwordMatches else {
                notice = AuthNotice(
                    message: L10n.tr("Passwords must match."),
                    kind: .error
                )
                focusedField = .confirmPassword
                return false
            }

            guard passwordStoredSafely else {
                notice = AuthNotice(
                    message: L10n.tr("Confirm that you stored the password safely."),
                    kind: .error
                )
                return false
            }
        }

        return true
    }

    private func attemptAuthentication() {
        guard !isSigningIn else { return }
        guard validateEmail(), validatePasswordStep() else { return }

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
            } catch let error as SupabaseServiceError {
                switch error {
                case .emailConfirmationRequired:
                    bootstrap.settingsStore.rememberAuthEmail(rememberMe ? normalizedEmail : nil)
                    password = ""
                    confirmPassword = ""
                    showPassword = false
                    showConfirmPassword = false
                    passwordStoredSafely = false
                    confirmationState = .inbox
                    move(to: .confirmation, direction: .forward)
                default:
                    notice = AuthNotice(message: error.localizedDescription, kind: .error)
                }
            } catch {
                notice = AuthNotice(message: error.localizedDescription, kind: .error)
            }
        }
    }
}

private struct AuthEntryField: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    let prompt: String
    let icon: String
    let isSecure: Bool
    @Binding var isVisible: Bool
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let focus: FocusState<LoginView.Field?>.Binding
    let field: LoginView.Field

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var fieldFill: Color {
        isDarkMode ? Color.white.opacity(0.06) : Color.white
    }

    private var borderColor: Color {
        isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.16)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.58) : Color.black.opacity(0.56))
                .frame(width: 22)

            Group {
                if isSecure && !isVisible {
                    SecureField(prompt, text: $text)
                        .focused(focus, equals: field)
                } else {
                    TextField(prompt, text: $text)
                        .focused(focus, equals: field)
                }
            }
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 17, weight: .medium, design: .rounded))

            if isSecure {
                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isDarkMode ? Color.white.opacity(0.58) : Color.black.opacity(0.52))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .accessibilityLabel(isVisible ? L10n.tr("Hide password") : L10n.tr("Show password"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }
}

private struct PasswordRequirementRow: View {
    let requirement: LoginView.PasswordRequirement

    private var successColor: Color { .accentColor }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: requirement.isMet ? "checklist.checked" : "checklist.unchecked")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    requirement.isMet
                        ? successColor
                        : Color(red: 0.89, green: 0.37, blue: 0.37)
                )

            Text(requirement.title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(
                    requirement.isMet
                        ? successColor
                        : Color(red: 0.89, green: 0.37, blue: 0.37)
                )
        }
    }
}

#Preview {
    LoginView(onSignedIn: {})
        .environment(AppBootstrap())
}
