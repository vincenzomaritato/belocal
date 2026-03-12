import SwiftData
import SwiftUI

struct AgentCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var plannerViewModel: PlannerViewModel
    @Bindable var homeViewModel: HomeViewModel

    private let styleLibrary = ["Beach", "Culture", "Food", "Nature", "Adventure", "Wellness"]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                commandStrip
                destinationPicker
                structuredInputs
                suggestionChips
                messagesSection
                composerSection
                toolResultsSection
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("Planning Agent"))
                .font(.headline)
            Text(L10n.tr("Chat-first orchestration"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.tr("Use commands like `/restaurants`, `/activities`, `/save` or write naturally."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var commandStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(plannerViewModel.commandHints, id: \.self) { command in
                    Button {
                        plannerViewModel.performQuickAction(
                            command,
                            toolRouter: bootstrap.toolRouter,
                            context: modelContext,
                            homeViewModel: homeViewModel,
                            bootstrap: bootstrap
                        )
                    } label: {
                        Text(command)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityTapTarget()
                }
            }
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Destination"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(L10n.tr("Destination"), selection: Binding(
                get: { plannerViewModel.draft.destinationId },
                set: { plannerViewModel.draft.destinationId = $0 }
            )) {
                Text(L10n.tr("Auto (top recommendation)")).tag(UUID?.none)
                ForEach(homeViewModel.destinations, id: \.id) { destination in
                    Text("\(destination.name), \(destination.country)").tag(Optional(destination.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var structuredInputs: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(L10n.tr("Budget"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L10n.f("€%d", Int(plannerViewModel.draft.budget)))
                        .font(.subheadline.weight(.semibold))
                }
                Slider(value: $plannerViewModel.draft.budget, in: 400...7000, step: 50)
            }

            HStack {
                DatePicker(L10n.tr("Start"), selection: $plannerViewModel.draft.startDate, displayedComponents: .date)
                DatePicker(L10n.tr("End"), selection: $plannerViewModel.draft.endDate, displayedComponents: .date)
            }

            Stepper(L10n.f("People: %d", plannerViewModel.draft.people), value: $plannerViewModel.draft.people, in: 1...8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(styleLibrary, id: \.self) { style in
                        let selected = plannerViewModel.draft.selectedStyles.contains(style)
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                plannerViewModel.applySuggestion(style)
                            }
                        } label: {
                            Text(L10n.style(style))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityTapTarget()
                        .accessibilityLabel(L10n.style(style))
                        .accessibilityValue(selected ? L10n.tr("Selected") : L10n.tr("Not selected"))
                        .accessibilityHint(L10n.tr("Adds or removes this style from your plan"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                actionChip(L10n.tr("Find restaurants"))
                actionChip(L10n.tr("Find activities"))
                actionChip(L10n.tr("Add a day"))
                actionChip(L10n.tr("Save Trip Draft"))
            }
        }
    }

    private var messagesSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(plannerViewModel.agentMessages.suffix(14), id: \.id) { message in
                    messageBubble(message)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 220, maxHeight: 320)
        .padding(.vertical, 4)
    }

    private var composerSection: some View {
        HStack {
            TextField(L10n.tr("Type a command or request"), text: $plannerViewModel.userMessage)
                .textFieldStyle(.roundedBorder)

            Button(L10n.tr("Send")) {
                plannerViewModel.sendMessage(
                    toolRouter: bootstrap.toolRouter,
                    context: modelContext,
                    homeViewModel: homeViewModel,
                    bootstrap: bootstrap
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var toolResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if plannerViewModel.isToolLoading.contains(.flights) || plannerViewModel.isToolLoading.contains(.restaurants) || plannerViewModel.isToolLoading.contains(.activities) {
                SkeletonView().frame(height: 74)
            }

            if !plannerViewModel.latestRestaurants.isEmpty {
                resultHeader(L10n.tr("Restaurants"))
                ForEach(plannerViewModel.latestRestaurants, id: \.id) { option in
                    Text(L10n.f("%@ • %@ • €%d", option.name, option.cuisine, Int(option.estimatedCost)))
                        .font(.caption)
                }
            }

            if !plannerViewModel.latestActivities.isEmpty {
                resultHeader(L10n.tr("Activities"))
                ForEach(plannerViewModel.latestActivities, id: \.id) { option in
                    Text(L10n.f("%@ • %@ • €%d", option.title, option.category, Int(option.estimatedCost)))
                        .font(.caption)
                }
            }
        }
    }

    private func actionChip(_ label: String) -> some View {
        Button {
            plannerViewModel.performQuickAction(
                label,
                toolRouter: bootstrap.toolRouter,
                context: modelContext,
                homeViewModel: homeViewModel,
                bootstrap: bootstrap
            )
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.gray.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
    }

    private func resultHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func messageBubble(_ message: AgentMessage) -> some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
            HStack {
                if message.isUser { Spacer(minLength: 30) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(message.body)
                        .font(.subheadline)
                }
                .padding(10)
                .background(message.isUser ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !message.isUser { Spacer(minLength: 30) }
            }

            if !message.suggestions.isEmpty && !message.isUser {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(message.suggestions, id: \.self) { suggestion in
                            actionChip(suggestion)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.agentcanvas") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)
    let plannerViewModel = PlannerViewModel()

    return AgentCanvasView(plannerViewModel: plannerViewModel, homeViewModel: homeViewModel)
        .environment(bootstrap)
        .modelContainer(container)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
