import SwiftUI
import AniliteKit

// MARK: - Binge planner

/// Schedules what you're watching into the time you actually have each day. Airing
/// shows are never scheduled before an episode is out.
struct PlannerView: View {
    @Environment(AppModel.self) private var model
    @State private var includedPlanning: Set<Int> = []
    @State private var showsBudget = false

    private let weekdays = Calendar.current.shortWeekdaySymbols

    var body: some View {
        @Bindable var model = model
        let items = planItems
        let plan = BingePlanner.plan(items, budget: model.settings.weeklyBudget, strategy: model.settings.planStrategy,
                                     start: Calendar.current.startOfDay(for: Date()), horizonDays: 180)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summary(plan, itemCount: items.count)
                budgetEditor
                Picker("Strategy", selection: $model.settings.planStrategy) {
                    ForEach(PlanStrategy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if items.isEmpty {
                    EmptyStateView(symbol: "calendar.badge.plus", title: "Nothing to plan",
                                   message: "Start watching something, or add titles from Planning below.")
                } else {
                    finishList(plan, items: items)
                    agenda(plan)
                }
                planningPicker
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .screenChrome("Binge Planner")
    }

    private var planItems: [PlanItem] {
        let active = model.library.entries(type: .anime).filter { $0.status.isActive }
        let planned = model.library.entries(type: .anime, status: .planning).filter { includedPlanning.contains($0.mediaId) }
        return (active + planned).map { entry in
            PlanItem(entry: entry, schedule: entry.media.airingSchedule?.nodes ?? [])
        }
    }

    private func summary(_ plan: BingePlan, itemCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "\(itemCount) titles · \(Formatting.duration(minutes: plan.totalMinutes)) scheduled")
            if let finish = plan.finishDate {
                Text("All done by \(finish.formatted(.dateTime.weekday(.wide).month().day()))")
                    .font(Typo.display(24))
                    .foregroundStyle(Theme.textPrimary)
            } else if !plan.unfinished.isEmpty {
                Text("Some shows are still airing")
                    .font(Typo.display(22))
                    .foregroundStyle(Theme.textPrimary)
                Text("Their finish depends on the broadcast schedule; everything released fits your plan.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 8)
    }

    private var budgetEditor: some View {
        @Bindable var model = model
        let budget = model.settings.weeklyBudget
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.standard) { showsBudget.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your week")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(Formatting.duration(minutes: budget.weeklyTotal)) a week")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            Capsule()
                                .fill(Theme.accent.opacity(0.85))
                                .frame(width: 6, height: max(4, CGFloat(budget.minutes[day]) / 6))
                        }
                    }
                    .frame(height: 40, alignment: .bottom)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showsBudget ? 180 : 0))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your week, \(Formatting.duration(minutes: budget.weeklyTotal)) a week. \(showsBudget ? "Collapse" : "Edit")")

            if showsBudget {
                ForEach(0..<7, id: \.self) { day in
                    Stepper(value: Binding(
                        get: { model.settings.weeklyBudget.minutes[day] },
                        set: { value in
                            var minutes = model.settings.weeklyBudget.minutes
                            minutes[day] = value
                            model.settings.weeklyBudget = WeeklyBudget(minutes: minutes)
                        }), in: 0...600, step: 15) {
                        HStack {
                            Text(weekdays[day]).frame(width: 46, alignment: .leading)
                            Text(budget.minutes[day] == 0 ? "Rest day" : Formatting.duration(minutes: budget.minutes[day]))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Button("Reset to a typical week") { model.settings.weeklyBudget = .standard }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accentCool)
            }
        }
        .padding(16)
        .surface()
    }

    private func finishList(_ plan: BingePlan, items: [PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Finish dates")
            ForEach(items) { item in
                HStack(spacing: 12) {
                    if let media = model.entry(item.mediaId)?.media {
                        PosterImage(media: media, width: 34, cornerRadius: 5)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.entry(item.mediaId).map { model.title($0.media) } ?? item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("\(item.units) left · \(Formatting.duration(minutes: item.units * item.minutesPerUnit))")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    if let date = plan.finishDates[item.mediaId] {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.positive)
                    } else {
                        Text("Airing")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.caution)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func agenda(_ plan: BingePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Next two weeks")
            ForEach(plan.days.prefix(14)) { day in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 2) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(Typo.micro)
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.accent : Theme.textTertiary)
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(width: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        if day.sessions.isEmpty {
                            Text(day.budget == 0 ? "Rest day" : "Free time")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        ForEach(day.sessions) { session in
                            HStack {
                                Text(model.entry(session.mediaId).map { model.title($0.media) } ?? session.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(session.units.count == 1 ? "Ep \(session.units.lowerBound)" : "Ep \(session.units.lowerBound)–\(session.units.upperBound)")
                                    .font(Typo.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if day.budget > 0 {
                            ProgressBar(progress: Double(day.used) / Double(max(1, day.budget)), tint: Theme.accent, height: 3)
                        }
                    }
                }
                .padding(12)
                .surface()
            }
        }
    }

    @ViewBuilder private var planningPicker: some View {
        let planning = model.library.entries(type: .anime, status: .planning)
        if !planning.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Add from Planning")
                ForEach(planning.prefix(30)) { entry in
                    Button {
                        Haptics.tick()
                        if includedPlanning.contains(entry.mediaId) { includedPlanning.remove(entry.mediaId) } else { includedPlanning.insert(entry.mediaId) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: includedPlanning.contains(entry.mediaId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(includedPlanning.contains(entry.mediaId) ? Theme.accent : Theme.textTertiary)
                            Text(model.title(entry.media))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let minutes = entry.media.totalMinutes {
                                Text(Formatting.duration(minutes: minutes))
                                    .font(Typo.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(includedPlanning.contains(entry.mediaId) ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Airing calendar

struct AiringCalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var schedules: [AiringSchedule] = []
    @State private var state: LoadState = .idle
    @State private var onlyMine = true

    var body: some View {
        @Bindable var model = model
        let days = AiringCalendar.group(schedules, library: model.library, onlyLibrary: onlyMine)
        List {
            Section {
                Toggle("Only shows in my library", isOn: $onlyMine.animation())
                Toggle("Remind me when episodes air", isOn: Binding(
                    get: { model.settings.airingReminders },
                    set: { enabled in
                        if enabled {
                            Task {
                                let granted = await AiringReminders.requestAuthorization()
                                model.settings.airingReminders = granted
                                if !granted { model.showBanner("Notifications are off for Anilite in Settings.") }
                            }
                        } else {
                            model.settings.airingReminders = false
                        }
                    }))
            }
            .listRowBackground(Color.white.opacity(0.05))

            switch state {
            case .failed(let message):
                ErrorBanner(message: message) { Task { await load(force: true) } }
                    .listRowBackground(Color.clear)
            case .loading where schedules.isEmpty:
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            default:
                if days.isEmpty {
                    EmptyStateView(symbol: "calendar", title: onlyMine ? "Nothing of yours airs this week" : "Nothing scheduled",
                                   message: onlyMine ? "Turn off the filter to see every show airing in the next seven days." : "Check back later.")
                        .listRowBackground(Color.clear)
                }
                ForEach(days) { day in
                    Section {
                        ForEach(day.slots) { slot in
                            AiringRow(slot: slot)
                                .listRowBackground(Color.white.opacity(slot.isInLibrary ? 0.07 : 0.03))
                        }
                    } header: {
                        Text(dayTitle(day.date))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.accent : Theme.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenChrome("Airing This Week")
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    /// Up to four pages (200 broadcasts) covering the next week, cached for three hours.
    private func load(force: Bool) async {
        state = .loading
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(7 * 86_400)
        var all: [AiringSchedule] = []
        do {
            for page in 1...4 {
                let response = try await model.client.fetch(Queries.airing(start: start, end: end, page: page),
                                                            policy: force ? .networkFirst : .cacheFirst)
                all += response.Page.airingSchedules
                if response.Page.pageInfo?.hasNextPage != true { break }
            }
            schedules = all.filter { !($0.media?.isAdult ?? false) }
            state = .loaded
        } catch {
            if schedules.isEmpty { state = .failed(AppModel.message(for: error)) } else { state = .loaded }
        }
    }
}

private struct AiringRow: View {
    let slot: AiringSlot
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink(value: Route.media(slot.media.id)) {
            HStack(spacing: 12) {
                Text(slot.airingAt.formatted(.dateTime.hour().minute()))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(slot.airingAt < Date() ? Theme.textTertiary : Theme.textPrimary)
                    .frame(width: 58, alignment: .leading)
                PosterImage(media: slot.media, width: 34, cornerRadius: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title(slot.media))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("Episode \(slot.episode)")
                        if slot.isInLibrary {
                            Text(slot.isCaughtUp ? "· you're caught up" : "· you're behind")
                                .foregroundStyle(slot.isCaughtUp ? Theme.positive : Theme.caution)
                        }
                    }
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Journal

struct JournalView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = Dictionary(grouping: model.journal) { entry in
            Calendar.current.dateInterval(of: .month, for: entry.createdAt)?.start ?? entry.createdAt
        }
        let months = groups.keys.sorted(by: >)
        List {
            if model.journal.isEmpty {
                EmptyStateView(symbol: "book.closed", title: "A quiet diary",
                               message: "Write a note from any title's page: a moment, a theory, a feeling. Notes stay on this device.")
                    .listRowBackground(Color.clear)
            }
            ForEach(months, id: \.self) { month in
                Section(month.formatted(.dateTime.month(.wide).year())) {
                    ForEach((groups[month] ?? []).sorted { $0.createdAt > $1.createdAt }) { entry in
                        NavigationLink(value: Route.media(entry.mediaId)) {
                            JournalNoteRow(entry: entry)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions {
                            Button(role: .destructive) { model.deleteJournal(entry.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .screenChrome("Journal")
    }
}

// MARK: - History

/// AniList activity history when available, otherwise finish dates from the library.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var loading = false

    var body: some View {
        List {
            if !model.activities.isEmpty {
                let groups = Dictionary(grouping: model.activities) { Calendar.current.startOfDay(for: $0.date) }
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                        ForEach(groups[day] ?? []) { activity in
                            ActivityRow(activity: activity)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            } else {
                let finished = model.library.all
                    .compactMap { entry -> (LibraryEntry, Date)? in
                        guard let date = entry.completedAt?.date() else { return nil }
                        return (entry, date)
                    }
                    .sorted { $0.1 > $1.1 }
                if finished.isEmpty {
                    EmptyStateView(symbol: "clock.arrow.circlepath", title: "No history yet",
                                   message: model.account.displayName == nil
                                       ? "Finish something and it will show up here."
                                       : "Your AniList activity will appear here after the next sync.")
                        .listRowBackground(Color.clear)
                } else {
                    Section("Finished") {
                        ForEach(finished, id: \.0.id) { pair in
                            MediaRow(media: pair.0.media, detail: "Finished \(pair.1.formatted(.dateTime.month().day().year()))")
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .screenChrome("History")
        .refreshable { await model.refreshActivities() }
        .task {
            if model.activities.isEmpty, model.account.displayName != nil, !loading {
                loading = true
                await model.refreshActivities()
                loading = false
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: ListActivity
    @Environment(AppModel.self) private var model

    var body: some View {
        if let media = activity.media {
            NavigationLink(value: Route.media(media.id)) {
                HStack(spacing: 12) {
                    PosterImage(media: media, width: 34, cornerRadius: 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title(media))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(description)
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text(activity.date.formatted(.dateTime.hour().minute()))
                        .font(Typo.caption.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var description: String {
        let status = (activity.status ?? "updated").capitalized(with: nil)
        if let progress = activity.progress, !progress.isEmpty { return "\(status) \(progress)" }
        return status
    }
}
