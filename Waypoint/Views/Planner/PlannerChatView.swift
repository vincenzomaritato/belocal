import SwiftUI
import UIKit

struct PlannerChatView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var homeViewModel: HomeViewModel
    @Binding var isPresented: Bool

    let initialPrompt: String
    let prefill: PlannerSuggestionPrefill?
    let conversation: PlannerConversation?
    let searchBarNamespace: Namespace.ID

    @State private var viewModel = PlannerChatViewModel()
    @GestureState private var dragOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0

    private let optionColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        GeometryReader { geometry in
            let baseBottomInset = max(18, geometry.safeAreaInsets.bottom + 10)
            let keyboardLift = max(0, keyboardHeight - geometry.safeAreaInsets.bottom)
            let dockBottomPadding = keyboardLift > 0 ? (keyboardLift + 8) : baseBottomInset
            let contentBottomBaseInset: CGFloat = viewModel.currentQuestion == nil ? 112 : 208
            let contentBottomInset = contentBottomBaseInset + keyboardLift

            ZStack(alignment: .bottom) {
                plannerPanel(contentBottomInset: contentBottomInset)
                    .padding(.top, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                bottomDock
                    .padding(.horizontal, 14)
                    .padding(.bottom, dockBottomPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .offset(y: max(0, dragOffset))
        .scaleEffect(1 - min(max(dragOffset / 350, 0), 1) * 0.02, anchor: .top)
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            let screenHeight = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? frame.maxY
            let overlap = max(0, screenHeight - frame.minY)

            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = overlap
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = 0
            }
        }
        .task(id: "\(conversation?.id.uuidString ?? "new")|\(initialPrompt)|\(prefill?.destinationLabel ?? "")|\(prefill?.budgetLabel ?? "")") {
            viewModel.configureLiveActivitiesSearchIfNeeded(bootstrap.liveActivitiesSearch)
            viewModel.configureAttractionInfoProviderIfNeeded(bootstrap.liveAttractionInfoLookup)
            let didLoad = viewModel.configurePersistence(
                context: modelContext,
                existingConversation: conversation
            )

            if !didLoad, let prefill {
                viewModel.applySuggestionPrefillIfNeeded(prefill)
            }

            if !didLoad {
                await viewModel.sendInitialPromptIfNeeded(initialPrompt, service: bootstrap.openAIChatService)
            }
        }
        .gesture(dismissGesture)
    }

    private func plannerPanel(contentBottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar
            schemaBoard
            messagesList(contentBottomInset: contentBottomInset)
        }
        .background(panelBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 32,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 32,
                style: .continuous
            )
            .stroke(panelStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 20, x: 0, y: 6)
    }

    private var panelStroke: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.28), Color.white.opacity(0.10)]
                : [Color.white.opacity(0.90), Color.white.opacity(0.34)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemGroupedBackground),
                Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 90, y: -80)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 64)
                .offset(x: -80, y: 120)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard value.translation.height > 0 else { return }
                state = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 130 {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        isPresented = false
                    }
                }
            }
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.13))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .accessibilityLabel(L10n.tr("Close planner chat"))
                .accessibilityHint(L10n.tr("Returns to the planner overview"))

                HStack(spacing: 8) {
                    Text(L10n.tr("Planner Studio"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    progressBadge
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        viewModel.restartPlannerJourney()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .accessibilityLabel(L10n.tr("Restart planner"))
                .accessibilityHint(L10n.tr("Clears current progress and starts a new planning journey"))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var progressBadge: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 3)

            Circle()
                .trim(from: 0, to: max(0.02, viewModel.progressValue))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.accentColor,
                            Color(red: 1.0, green: 0.68, blue: 0.22)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(viewModel.progressLabel)
                .font(.system(size: 8, weight: .bold))
                .monospacedDigit()
        }
        .frame(width: 24, height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Planner progress"))
        .accessibilityValue(viewModel.progressLabel)
    }

    private var schemaBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(viewModel.schemaNodes) { node in
                    schemaNodeCard(node)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.26))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }

    private func schemaNodeCard(_ node: PlannerSchemaNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: node.isCompleted ? "checkmark.circle.fill" : node.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(node.isCompleted ? Color.accentColor : Color.secondary)

                Text(node.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Text(node.value ?? L10n.tr("Waiting..."))
                .font(.caption2)
                .foregroundStyle(node.value == nil ? .secondary : .primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 138, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    node.isCurrent
                    ? Color.accentColor.opacity(0.85)
                    : Color.white.opacity(colorScheme == .dark ? 0.18 : 0.58),
                    lineWidth: node.isCurrent ? 1.5 : 1
                )
        )
    }

    private func messagesList(contentBottomInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if !viewModel.answerSummaries.isEmpty {
                        summaryPills
                    }

                    if !viewModel.contextualActionGroups.isEmpty {
                        contextualActionBoard
                    }

                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }

                    if viewModel.isSending || viewModel.isGeneratingFinalReport || viewModel.isPersistingBrief {
                        processingIndicator
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, contentBottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.map(\.id)) { _, _ in
                guard let targetID = currentScrollTargetID() else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(targetID, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.text ?? "") { _, _ in
                guard let targetID = currentScrollTargetID() else { return }
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo(targetID, anchor: .bottom)
                }
            }
            .onChange(of: keyboardHeight) { _, _ in
                guard let targetID = currentScrollTargetID() else { return }
                withAnimation(.easeOut(duration: 0.20)) {
                    proxy.scrollTo(targetID, anchor: .bottom)
                }
            }
            .onAppear {
                guard let targetID = currentScrollTargetID() else { return }
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        }
    }

    private var summaryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.answerSummaries) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var bottomDock: some View {
        VStack(spacing: 10) {
            if let question = viewModel.currentQuestion {
                questionCard(question)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composerBar
        }
    }

    private func questionCard(_ question: PlannerQuestionStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: question.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color(red: 1.0, green: 0.65, blue: 0.20)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.localizedQuestionTitle(for: question.key))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(viewModel.localizedQuestionSubtitle(for: question.key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(viewModel.progressLabel)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: optionColumns, spacing: 8) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        Task {
                            await viewModel.submitQuickOption(option, service: bootstrap.openAIChatService)
                        }
                    } label: {
                        Text(viewModel.localizedOption(option, for: question.key))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.82))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityTapTarget()
                    .disabled(viewModel.isBusy)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await viewModel.submitSurpriseOption(service: bootstrap.openAIChatService)
                    }
                } label: {
                    Label(L10n.tr("Surprise Me"), systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .disabled(viewModel.isBusy)

                Button {
                    Task {
                        await viewModel.skipCurrentQuestion(service: bootstrap.openAIChatService)
                    }
                } label: {
                    Label(L10n.tr("Skip"), systemImage: "forward.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .disabled(viewModel.isBusy)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(panelStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.10), radius: 12, x: 0, y: 8)
    }

    private var composerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField(viewModel.composerPlaceholder, text: $viewModel.composerText, axis: .vertical)
                .lineLimit(1 ... 4)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .onSubmit {
                    Task {
                        await viewModel.sendCurrentMessage(service: bootstrap.openAIChatService)
                    }
                }

            let hasText = !viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            Button {
                guard hasText else { return }
                Task {
                    await viewModel.sendCurrentMessage(service: bootstrap.openAIChatService)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(hasText ? Color.white : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        Group {
                            if hasText {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.accentColor,
                                                Color(red: 1.0, green: 0.65, blue: 0.20)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
            .accessibilityTapTarget()
            .disabled(viewModel.isBusy || !hasText)
            .accessibilityLabel(L10n.tr("Send message"))
            .accessibilityHint(hasText ? L10n.tr("Sends the current message to Planner Studio") : L10n.tr("Type a message to enable sending"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(panelStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 12, x: 0, y: 6)
        .matchedGeometryEffect(
            id: "planner-chat-search-bar",
            in: searchBarNamespace,
            properties: .frame,
            anchor: .center,
            isSource: isPresented
        )
    }

    private func messageRow(_ message: PlannerChatMessage) -> some View {
        let isUser = message.sender == .user
        let bubbleMaxWidth = min(currentScreenWidth * 0.80, 520)

        return HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 44)

                Text(message.text)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color(red: 0.93, green: 0.47, blue: 0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.92),
                                        Color.accentColor.opacity(0.88),
                                        Color(red: 1.0, green: 0.64, blue: 0.20).opacity(0.52)
                                    ],
                                    center: .topLeading,
                                    startRadius: 1,
                                    endRadius: 16
                                )
                            )
                            .frame(width: 18, height: 18)
                            .padding(.top, 7)

                        assistantMessageContent(
                            message.text,
                            isStreaming: isStreamingAssistantMessage(message)
                        )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .fill(
                                        colorScheme == .dark
                                        ? Color.white.opacity(0.08)
                                        : Color.white.opacity(0.88)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.07), lineWidth: 1)
                            )
                            .shadow(
                                color: .black.opacity(colorScheme == .dark ? 0.22 : 0.06),
                                radius: 10,
                                x: 0,
                                y: 3
                            )

                        Spacer(minLength: 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func assistantMessageContent(_ text: String, isStreaming: Bool) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && isStreaming {
            streamingTypingIndicator
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(markdownBlocks(from: text)) { block in
                    markdownBlockView(block)
                }

                if isStreaming {
                    streamingCaret
                        .padding(.top, 8)
                }
            }
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func markdownBlockView(_ block: PlannerMarkdownBlock) -> some View {
        switch block.style {
        case .spacer:
            Color.clear
                .frame(height: 10)
        case .heading(let level):
            markdownText(block.raw)
                .font(headingFont(level: level))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(.top, 4)
                .padding(.bottom, 6)
        case .list:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parsedListItems(from: block.raw).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.marker)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .leading)

                        markdownText(item.text)
                            .font(.system(size: 15.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.bottom, 8)
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 3)
                markdownText(quoteBody(from: block.raw))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 6)
        case .code:
            codeBlockView(block.raw)
                .padding(.bottom, 8)
        case .table:
            ScrollView(.horizontal, showsIndicators: false) {
                markdownText(block.raw)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.20 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.bottom, 8)
        case .paragraph:
            markdownText(block.raw)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .padding(.bottom, 6)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 22, weight: .bold, design: .rounded)
        case 2:
            return .system(size: 20, weight: .bold, design: .rounded)
        case 3:
            return .system(size: 18, weight: .bold, design: .rounded)
        case 4:
            return .system(size: 17, weight: .semibold, design: .rounded)
        case 5:
            return .system(size: 16, weight: .semibold, design: .rounded)
        default:
            return .system(size: 15, weight: .semibold, design: .rounded)
        }
    }

    private func isStreamingAssistantMessage(_ message: PlannerChatMessage) -> Bool {
        guard message.sender == .assistant else { return false }
        guard viewModel.isSending else { return false }
        return viewModel.messages.last?.id == message.id
    }

    private var streamingTypingIndicator: some View {
        HStack(spacing: 5) {
            TimelineView(.animation(minimumInterval: 0.16)) { context in
                let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.16)
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(frame % 3 == index ? 0.92 : 0.24)
                    }
                }
            }
        }
        .frame(minWidth: 24, minHeight: 16, alignment: .leading)
    }

    private var streamingCaret: some View {
        TimelineView(.animation(minimumInterval: 0.28)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.28)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: 10, height: 2.5)
                .opacity(frame.isMultiple(of: 2) ? 0.96 : 0.22)
        }
        .frame(width: 10, height: 3, alignment: .leading)
    }

    private func codeBlockView(_ raw: String) -> some View {
        let code = codeBody(from: raw)
        return ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.26 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func codeBody(from raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return raw }

        var body = lines
        if body.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
            body.removeFirst()
        }
        if body.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
            body.removeLast()
        }

        let joined = body.joined(separator: "\n")
        return joined.trimmingCharacters(in: .newlines)
    }

    private func markdownBlocks(from rawText: String) -> [PlannerMarkdownBlock] {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }
        let lines = normalized.components(separatedBy: .newlines)

        var blocks: [PlannerMarkdownBlock] = []
        var paragraphLines: [String] = []
        var listLines: [String] = []
        var quoteLines: [String] = []
        var tableLines: [String] = []
        var codeLines: [String] = []
        var isInCodeFence = false
        var blockID = 0

        func appendBlock(_ style: PlannerMarkdownBlockStyle, _ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .newlines)
            if case .spacer = style {
                // allow explicit spacer blocks
            } else if trimmed.isEmpty {
                return
            }
            blocks.append(.init(id: blockID, raw: trimmed, style: style))
            blockID += 1
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            appendBlock(.paragraph, paragraphLines.joined(separator: "\n"))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushList() {
            guard !listLines.isEmpty else { return }
            appendBlock(.list, listLines.joined(separator: "\n"))
            listLines.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            appendBlock(.quote, quoteLines.joined(separator: "\n"))
            quoteLines.removeAll(keepingCapacity: true)
        }

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            if tableLines.count >= 2, isMarkdownTableSeparator(tableLines[1].trimmingCharacters(in: .whitespaces)) {
                appendBlock(.table, tableLines.joined(separator: "\n"))
            } else {
                paragraphLines.append(contentsOf: tableLines)
            }
            tableLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isInCodeFence {
                    codeLines.append(line)
                    appendBlock(.code, codeLines.joined(separator: "\n"))
                    codeLines.removeAll(keepingCapacity: true)
                    isInCodeFence = false
                } else {
                    flushParagraph()
                    flushList()
                    flushQuote()
                    flushTable()
                    isInCodeFence = true
                    codeLines = [line]
                }
                continue
            }

            if isInCodeFence {
                codeLines.append(line)
                continue
            }

            if !isInCodeFence && trimmed.isEmpty {
                flushParagraph()
                flushList()
                flushQuote()
                flushTable()
                let hasTrailingSpacer: Bool
                if let lastStyle = blocks.last?.style, case .spacer = lastStyle {
                    hasTrailingSpacer = true
                } else {
                    hasTrailingSpacer = false
                }

                if !hasTrailingSpacer {
                    appendBlock(.spacer, "")
                }
                continue
            }

            if let level = markdownHeadingLevel(from: trimmed) {
                flushParagraph()
                flushList()
                flushQuote()
                flushTable()
                let headingText = trimmed
                    .drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                appendBlock(.heading(level: level), headingText)
                continue
            }

            if isListLine(trimmed) {
                flushParagraph()
                flushQuote()
                flushTable()
                listLines.append(trimmed)
                continue
            } else {
                flushList()
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushTable()
                quoteLines.append(trimmed)
                continue
            } else {
                flushQuote()
            }

            if looksLikeTableLine(trimmed) {
                flushParagraph()
                tableLines.append(trimmed)
                continue
            } else {
                flushTable()
            }

            paragraphLines.append(line)
        }

        if isInCodeFence, !codeLines.isEmpty {
            appendBlock(.code, codeLines.joined(separator: "\n"))
        }
        flushParagraph()
        flushList()
        flushQuote()
        flushTable()

        if blocks.isEmpty {
            appendBlock(.paragraph, normalized)
        }

        while let first = blocks.first, isSpacerStyle(first.style) {
            blocks.removeFirst()
        }
        while let last = blocks.last, isSpacerStyle(last.style) {
            blocks.removeLast()
        }

        return blocks
    }

    private func isSpacerStyle(_ style: PlannerMarkdownBlockStyle) -> Bool {
        if case .spacer = style { return true }
        return false
    }

    private func markdownHeadingLevel(from line: String) -> Int? {
        let scalars = Array(line)
        var level = 0
        for char in scalars {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level) else { return nil }
        guard scalars.count > level, scalars[level].isWhitespace else { return nil }
        return level
    }

    private func isListLine(_ line: String) -> Bool {
        line.range(of: #"^([-*+]|\d+[\.\)])\s+"#, options: .regularExpression) != nil
    }

    private func looksLikeTableLine(_ line: String) -> Bool {
        line.contains("|")
    }

    private func isMarkdownTableSeparator(_ line: String) -> Bool {
        let collapsed = line.replacingOccurrences(of: " ", with: "")
        return collapsed.range(of: #"^\|?[:\-|]+\|?$"#, options: .regularExpression) != nil
    }

    private func parsedListItems(from raw: String) -> [(marker: String, text: String)] {
        raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if let range = line.range(of: #"^(\d+[\.\)])\s+"#, options: .regularExpression) {
                    let marker = String(line[range]).trimmingCharacters(in: .whitespaces)
                    let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (marker: marker, text: text)
                }
                if let range = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                    let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (marker: "•", text: text)
                }
                return (marker: "•", text: line)
            }
    }

    private func quoteBody(from raw: String) -> String {
        raw
            .components(separatedBy: .newlines)
            .map { line in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(">") {
                    trimmed.removeFirst()
                }
                return trimmed.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }

    private func markdownText(_ raw: String) -> Text {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attributed = try? AttributedString(
            markdown: trimmed,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return Text(attributed)
        }
        return Text(trimmed)
    }

    private var contextualActionBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Agent Actions"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(viewModel.contextualActionGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                        Text(group.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(group.actions) { action in
                                Button {
                                    Task {
                                        await viewModel.runContextualAction(action, service: bootstrap.openAIChatService)
                                    }
                                } label: {
                                    Label(action.title, systemImage: action.icon)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(uiColor: .secondarySystemGroupedBackground),
                                                            Color(uiColor: .tertiarySystemGroupedBackground)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        )
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isBusy)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
        .padding(.bottom, 2)
    }

    private func finalReportCard(_ report: PlannerFinalReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color(red: 1.0, green: 0.63, blue: 0.22)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(report.headline)
                        .font(.headline.weight(.semibold))
                    Text(L10n.f("Final Trip Brief • %@", report.generatedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        viewModel.saveFinalBriefToMyPlan(
                            context: modelContext,
                            homeViewModel: homeViewModel,
                            bootstrap: bootstrap
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityTapTarget()
                    .disabled(viewModel.isBusy || viewModel.isPersistingBrief)
                    .accessibilityLabel(L10n.tr("Save final brief"))
                    .accessibilityHint(L10n.tr("Saves this brief to My Plan"))

                    Button {
                        Task {
                            await viewModel.runContextualAction(.refreshBrief, service: bootstrap.openAIChatService)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityTapTarget()
                    .disabled(viewModel.isBusy)
                    .accessibilityLabel(L10n.tr("Refresh final brief"))
                    .accessibilityHint(L10n.tr("Regenerates the final travel brief"))
                }
            }

            Text(report.overview)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            reportFactsGrid(report)

            if !report.attractions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel(L10n.tr("Top Attractions"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(report.attractions.prefix(8)) { attraction in
                                attractionInteractiveCard(attraction)
                            }
                        }
                    }
                }
            }

            if !report.dailyHighlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel(L10n.tr("Daily Highlights"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(report.dailyHighlights.prefix(5)) { day in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(day.day)
                                        .font(.caption.weight(.bold))
                                    Text(L10n.f("AM: %@", day.morning))
                                        .font(.footnote)
                                    Text(L10n.f("PM: %@", day.afternoon))
                                        .font(.footnote)
                                    Text(L10n.f("EVE: %@", day.evening))
                                        .font(.footnote)
                                    Divider()
                                    Text(L10n.f("Rain: %@", day.rainFallback))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(width: 210, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                                )
                            }
                        }
                    }
                }
            }

            if !report.checklist.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(L10n.tr("Checklist"))
                    ForEach(Array(report.checklist.prefix(7).enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "\(index + 1).circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 1)
                            Text(line)
                                .font(.caption)
                        }
                    }
                }
            }

            if !report.notes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sectionLabel(L10n.tr("Notes"))
                    ForEach(Array(report.notes.prefix(4).enumerated()), id: \.offset) { _, note in
                        Text(L10n.f("• %@", note))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .secondarySystemGroupedBackground),
                            Color(uiColor: .tertiarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(panelStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.1), radius: 14, x: 0, y: 8)
    }

    private func attractionInteractiveCard(_ attraction: PlannerFinalAttraction) -> some View {
        let liveInfo = viewModel.attractionInfo(for: attraction)
        let isLoadingLiveInfo = viewModel.isLoadingAttractionInfo(for: attraction)
        let heroImageURL = liveInfo?.wikiImageURL

        return VStack(alignment: .leading, spacing: 8) {
            if let heroImageURL {
                AsyncImage(url: heroImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        attractionHeroPlaceholder
                    case .empty:
                        attractionHeroPlaceholder
                    @unknown default:
                        attractionHeroPlaceholder
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(attraction.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Text(attraction.estimatedCost)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if let address = liveInfo?.address, !address.isEmpty {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(liveInfo?.wikiSummary ?? liveInfo?.placeSummary ?? attraction.why)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Label(attraction.bestTime, systemImage: "clock")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            if let liveInfo {
                HStack(spacing: 6) {
                    if let ratingText = attractionRatingText(liveInfo) {
                        infoPill(text: ratingText, icon: "star.fill", tint: Color.yellow.opacity(0.8))
                    }
                    if let openText = attractionOpenText(liveInfo) {
                        infoPill(
                            text: openText,
                            icon: "clock.badge.checkmark",
                            tint: liveInfo.openNow == true ? Color.green.opacity(0.78) : Color.orange.opacity(0.76)
                        )
                    }
                    if let weatherText = attractionWeatherText(liveInfo) {
                        infoPill(text: weatherText, icon: "cloud.sun.fill", tint: Color.blue.opacity(0.78))
                    }
                    if let priceLevel = liveInfo.priceLevel {
                        infoPill(text: priceLevel, icon: "eurosign.circle.fill", tint: Color.purple.opacity(0.72))
                    }
                }

                if !liveInfo.placeTypes.isEmpty {
                    Text(liveInfo.placeTypes.prefix(3).map(readablePlaceType).joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let phone = liveInfo.phoneNumber, !phone.isEmpty {
                    Label(phone, systemImage: "phone.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let mapsURL = liveInfo.mapsURL {
                        Button {
                            openURL(mapsURL)
                        } label: {
                            Label(L10n.tr("Maps"), systemImage: "map")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.16))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityTapTarget()
                    }

                    if let wikiURL = liveInfo.wikiArticleURL {
                        Button {
                            openURL(wikiURL)
                        } label: {
                            Label(L10n.tr("Wiki"), systemImage: "book.closed")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.blue.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityTapTarget()
                    }

                    if let websiteURL = liveInfo.websiteURL {
                        Button {
                            openURL(websiteURL)
                        } label: {
                            Label(L10n.tr("Website"), systemImage: "safari")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.green.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityTapTarget()
                    }
                }
                .frame(maxWidth: .infinity)
            } else if isLoadingLiveInfo {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.tr("Loading live info..."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 6) {
                attractionActionButton(
                    title: L10n.tr("Details"),
                    icon: "info.circle",
                    action: .details,
                    attraction: attraction
                )
                attractionActionButton(
                    title: L10n.tr("In plan"),
                    icon: "calendar.badge.plus",
                    action: .fitInDayPlan,
                    attraction: attraction
                )
                attractionActionButton(
                    title: L10n.tr("Alt"),
                    icon: "arrow.triangle.2.circlepath",
                    action: .findAlternative,
                    attraction: attraction
                )
            }
        }
        .padding(11)
        .frame(width: 256, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .task(id: attraction.id) {
            viewModel.preloadAttractionInfoIfNeeded(for: attraction)
        }
    }

    private var attractionHeroPlaceholder: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.36),
                Color.blue.opacity(0.30)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        )
    }

    private func readablePlaceType(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func infoPill(text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.42), lineWidth: 1)
            )
    }

    private func attractionRatingText(_ info: AttractionCardLiveInfo) -> String? {
        guard let rating = info.rating else { return nil }
        if let reviewCount = info.reviewCount, reviewCount > 0 {
            return String(format: "%.1f (%d)", rating, reviewCount)
        }
        return String(format: "%.1f", rating)
    }

    private func attractionOpenText(_ info: AttractionCardLiveInfo) -> String? {
        guard let openNow = info.openNow else { return nil }
        return openNow ? L10n.tr("Open now") : L10n.tr("Closed now")
    }

    private func attractionWeatherText(_ info: AttractionCardLiveInfo) -> String? {
        guard let temperatureC = info.temperatureC else { return nil }
        let rounded = Int(temperatureC.rounded())
        if let summary = info.weatherSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return "\(rounded)°C • \(summary.capitalized)"
        }
        return "\(rounded)°C"
    }

    private func currentScrollTargetID() -> AnyHashable? {
        guard let lastMessage = viewModel.messages.last else { return nil }
        return AnyHashable(lastMessage.id)
    }

    private func attractionActionButton(
        title: String,
        icon: String,
        action: PlannerAttractionCardAction,
        attraction: PlannerFinalAttraction
    ) -> some View {
        Button {
            Task {
                await viewModel.runAttractionCardAction(
                    action,
                    attraction: attraction,
                    service: bootstrap.openAIChatService
                )
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
    }

    private func reportFactsGrid(_ report: PlannerFinalReport) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                factCard(L10n.tr("Focus"), value: report.destinationFocus, icon: "location.fill")
                factCard(L10n.tr("Best Window"), value: report.bestTravelWindow, icon: "calendar")
            }

            HStack(spacing: 8) {
                factCard(L10n.tr("Budget"), value: report.budgetSnapshot, icon: "wallet.pass.fill")
                factCard(L10n.tr("Transport"), value: report.transportStrategy, icon: "tram")
            }
        }
    }

    private func factCard(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var finalReportLoadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(L10n.tr("Building the Final Trip Brief with attractions and logistics..."))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var processingIndicator: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Color.secondary.opacity(0.65))
                .frame(width: 8, height: 8)

            Text(
                viewModel.stage == .generating
                ? L10n.tr("Building the full planner")
                : viewModel.isPersistingBrief
                ? L10n.tr("Saving to My Plan")
                : viewModel.isGeneratingFinalReport
                ? L10n.tr("Composing final trip brief")
                : L10n.tr("Thinking")
            )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TimelineView(.animation(minimumInterval: 0.18)) { context in
                let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.18)
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(frame % 3 == index ? 0.92 : 0.28)
                    }
                }
            }

            Spacer()
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var currentScreenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? 390
    }
}

private enum PlannerMarkdownBlockStyle {
    case spacer
    case heading(level: Int)
    case list
    case quote
    case code
    case table
    case paragraph
}

private struct PlannerMarkdownBlock: Identifiable {
    let id: Int
    let raw: String
    let style: PlannerMarkdownBlockStyle
}
