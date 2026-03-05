import SwiftUI

struct TimelineBuilderView: View {
    @Bindable var plannerViewModel: PlannerViewModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Plan timeline")
                        .font(.headline)
                    Spacer()
                    Button {
                        plannerViewModel.addDay()
                    } label: {
                        Label("Add Day", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if plannerViewModel.draft.timeline.isEmpty {
                    Text("No days yet. Add one to begin planning.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(plannerViewModel.draft.timeline, id: \.id) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(day.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Button(role: .destructive) {
                                        plannerViewModel.removeDay(day)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("Delete \(day.title)")
                                }

                                if day.activities.isEmpty {
                                    Text("No activities yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(day.activities, id: \.id) { activity in
                                        Text("• \(activity.title)")
                                            .font(.caption)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: plannerViewModel.moveDays)
                    }
                    .frame(height: 260)
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    let plannerViewModel = PlannerViewModel()
    plannerViewModel.draft.timeline = [
        DayPlan(dayIndex: 1, activities: [DraftActivity(type: .activity, title: "Old Town Walk")]),
        DayPlan(dayIndex: 2, activities: [DraftActivity(type: .restaurant, title: "Riverside Dinner")]),
        DayPlan(dayIndex: 3)
    ]

    return TimelineBuilderView(plannerViewModel: plannerViewModel)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
