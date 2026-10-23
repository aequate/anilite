import SwiftUI
import AniliteKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget
    @State private var confirmSignOut = false
    @State private var syncing = false

    /// Regions with distinct anime licensing. "Automatic" follows the device.
    private static let regions = ["US", "CA", "GB", "IE", "AU", "NZ", "DE", "AT", "CH", "FR", "BE", "NL", "ES", "IT", "PT",
                                  "SE", "NO", "DK", "FI", "PL", "BR", "MX", "AR", "CL", "CO", "IN", "JP", "KR", "TW", "HK",
                                  "SG", "MY", "PH", "ID", "TH", "VN", "ZA", "AE", "SA", "TR"]

    var body: some View {
        @Bindable var model = model
        Form {
            account

            Section {
                Picker("Titles in", selection: $model.settings.titleLanguage) {
                    ForEach(TitleLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Display")
            }

            Section {
                Picker("Spoiler Shield", selection: $model.settings.spoilerLevel) {
                    ForEach(SpoilerLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if !model.unlockedSpoilers.isEmpty {
                    Text("\(model.unlockedSpoilers.count) title\(model.unlockedSpoilers.count == 1 ? " has" : "s have") spoilers unlocked. Relock them from each title's menu.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Spoilers")
            } footer: {
                Text(model.settings.spoilerLevel.summary)
            }

            Section {
                Picker("Region", selection: $model.settings.regionOverride) {
                    Text("Automatic\(StreamingResolver.currentRegion.map { " (\(regionName($0)))" } ?? "")").tag(String?.none)
                    ForEach(Self.regions, id: \.self) { code in
                        Text(regionName(code)).tag(String?.some(code))
                    }
                }
            } header: {
                Text("Where to watch")
            } footer: {
                Text("Used to say whether a service is offered where you are. Anilite only shows availability it can verify, and links go to official services.")
            }

            Section {
                Picker("Visual effects", selection: $model.settings.effects) {
                    ForEach(EffectsPreference.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Haptics", isOn: $model.settings.haptics)
            } header: {
                Text("Motion & feel")
            } footer: {
                Text("\(model.settings.effects.detail) \(budget.statusSummary)")
            }

            Section {
                Toggle("Airing reminders", isOn: Binding(
                    get: { model.settings.airingReminders },
                    set: { enabled in
                        guard enabled else { model.settings.airingReminders = false; return }
                        Task {
                            let granted = await AiringReminders.requestAuthorization()
                            model.settings.airingReminders = granted
                            if !granted { model.showBanner("Allow notifications for Anilite in the Settings app.") }
                        }
                    }))
                if model.settings.airingReminders {
                    Picker("Remind me", selection: $model.settings.reminderLeadMinutes) {
                        Text("When it airs").tag(0)
                        Text("15 minutes after").tag(15)
                        Text("30 minutes after").tag(30)
                        Text("1 hour after").tag(60)
                        Text("3 hours after").tag(180)
                    }
                }
                Stepper("Tonight: \(Formatting.duration(minutes: model.settings.tonightMinutes))",
                        value: $model.settings.tonightMinutes, in: 20...360, step: 10)
                NavigationLink("Weekly watch time", value: Route.planner)
            } header: {
                Text("Scheduling")
            } footer: {
                Text("Reminders cover shows you're watching or planning. Streaming services often post episodes a little after broadcast. “Tonight” is how much time Discover plans for.")
            }

            Section {
                Button("Clear image & data caches") { Task { await model.clearCaches() } }
                if !model.queue.isEmpty {
                    LabeledContent("Waiting to sync", value: "\(model.queue.count) change\(model.queue.count == 1 ? "" : "s")")
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Your library, journal, shelves and clubs are stored on this device. Clearing caches never deletes them.")
            }

            Section {
                NavigationLink("Anime glossary", value: Route.glossary)
                if let url = URL(string: "https://anilist.co") {
                    Link("Data provided by AniList", destination: url)
                }
                if let url = URL(string: "https://docs.anilist.co/guide/terms-of-use") {
                    Link("AniList API terms", destination: url)
                }
                LabeledContent("Version", value: appVersion)
            } header: {
                Text("About")
            } footer: {
                Text("Anilite is an independent app and isn't affiliated with AniList or any studio or publisher. Artwork belongs to its rights holders. Anilite never hosts or links to unlicensed video or scans.")
            }
        }
        .scrollContentBackground(.hidden)
        .screenChrome("Settings")
        .confirmationDialog(signOutTitle, isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(signOutAction, role: .destructive) { Task { await model.signOut() } }
        } message: {
            Text(signOutMessage)
        }
    }

    @ViewBuilder private var account: some View {
        Section {
            LabeledContent("Account", value: model.account.summary)
            if let synced = model.library.lastSynced {
                LabeledContent("Last synced", value: synced.formatted(.relative(presentation: .named)))
            }
            switch model.account {
            case .connected:
                Button {
                    Task {
                        syncing = true
                        await model.flush()
                        await model.syncLibrary(force: true)
                        syncing = false
                    }
                } label: {
                    HStack {
                        Text("Sync now")
                        if syncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(syncing)
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            case .publicProfile:
                if AuthService.isConfigured {
                    Button("Sign in to edit") { Task { await model.signIn() } }
                }
                Button("Stop following this profile", role: .destructive) { confirmSignOut = true }
            case .local:
                if AuthService.isConfigured {
                    Button("Connect AniList") { Task { await model.signIn() } }
                }
            case .undecided:
                EmptyView()
            }
        } header: {
            Text("Library")
        } footer: {
            if model.account == .local {
                Text("Connecting AniList uploads your on-device library so nothing is lost.")
            }
        }
    }

    private var signOutTitle: String {
        model.account.isConnected ? "Sign out of AniList?" : "Stop following?"
    }

    private var signOutAction: String {
        model.account.isConnected ? "Sign out" : "Stop following"
    }

    private var signOutMessage: String {
        let pending = model.queue.count
        if model.account.isConnected && pending > 0 {
            return "\(pending) change\(pending == 1 ? " hasn't" : "s haven't") synced yet and will be lost. Your AniList account is unaffected."
        }
        return "Your journal, shelves and clubs stay on this device."
    }

    private func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Glossary

struct GlossaryView: View {
    @State private var query = ""

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let terms = Glossary.terms.filter { term in
            trimmed.isEmpty
                || term.term.lowercased().contains(trimmed)
                || term.aliases.contains { $0.lowercased().contains(trimmed) }
                || term.definition.lowercased().contains(trimmed)
        }
        List {
            ForEach(GlossaryTerm.Category.allCases, id: \.self) { category in
                let inCategory = terms.filter { $0.category == category }
                if !inCategory.isEmpty {
                    Section(category.rawValue) {
                        ForEach(inCategory) { term in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(term.term)
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(term.definition)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !term.aliases.isEmpty {
                                    Text("Also: \(term.aliases.joined(separator: ", "))")
                                        .font(Typo.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if terms.isEmpty {
                Text("No term matches “\(query)”. Try the Concierge — it can explain more.")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Search terms")
        .screenChrome("Glossary")
    }
}
