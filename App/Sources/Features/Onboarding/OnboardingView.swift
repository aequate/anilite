import SwiftUI
import AniliteKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(EffectsBudget.self) private var budget

    @State private var appeared = false
    @State private var showProfileField = false
    @State private var userName = ""
    @State private var profileError: String?
    @State private var working = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Theme.ink0.ignoresSafeArea()
            AtmosphereView(atmosphere: .brand, intensity: 1)
                .ignoresSafeArea()
            LinearGradient(colors: [.clear, Theme.ink0.opacity(0.65), Theme.ink0], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Spacer(minLength: 70)
                    header
                    promises
                    spoilerComfort
                    choices
                    footnote
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            withAnimation(budget.allowsPhysics ? .spring(response: 0.9, dampingFraction: 0.85).delay(0.1) : .easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ANILITE")
                .font(Typo.display(46))
                .tracking(4)
                .foregroundStyle(
                    LinearGradient(colors: [Theme.textPrimary, Theme.brand.opacity(0.9), Theme.brandCool], startPoint: .leading, endPoint: .trailing)
                )
                .accessibilityAddTraits(.isHeader)
            Text("Every anime and manga you love, in one living universe.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Find what fits your mood tonight, see exactly where the manga picks up, and never get spoiled on the way.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var promises: some View {
        VStack(alignment: .leading, spacing: 14) {
            promise("point.3.connected.trianglepath.dotted", "Universe Atlas", "Sequels, films, source manga and the people behind them, mapped.")
            promise("eye.slash", "Spoiler Shield", "Tags, cast and synopses stay hidden until you get there.")
            promise("calendar.badge.clock", "Plans that fit your week", "Binge plans, airing reminders and finish-date forecasts.")
        }
        .padding(18)
        .glassSurface()
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.brandCool)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var spoilerComfort: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Spoiler comfort")
            Picker("Spoiler comfort", selection: $model.settings.spoilerLevel) {
                ForEach(SpoilerLevel.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            Text(model.settings.spoilerLevel.summary)
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var choices: some View {
        VStack(spacing: 12) {
            if AuthService.isConfigured {
                Button {
                    Task {
                        working = true
                        await model.signIn()
                        working = false
                    }
                } label: {
                    Label("Connect AniList", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlowButtonStyle())
                .disabled(working)
                .accessibilityHint("Signs in on anilist.co so edits sync both ways")
            }

            if showProfileField {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "at").foregroundStyle(Theme.textTertiary)
                        TextField("AniList username", text: $userName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($nameFocused)
                            .onSubmit(followProfile)
                        if working {
                            ProgressView()
                        } else {
                            Button("Follow", action: followProfile)
                                .font(.subheadline.weight(.bold))
                                .disabled(userName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(14)
                    .glassSurface(cornerRadius: 16)
                    if let profileError {
                        Text(profileError).font(.footnote).foregroundStyle(Theme.negative)
                    }
                    Text("Read-only: you'll see their library, Taste DNA and plans. Nothing is changed on AniList.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showProfileField = true }
                    nameFocused = true
                } label: {
                    Label("Use a public AniList profile", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
            }

            Button {
                Haptics.success()
                model.useLocalLibrary()
            } label: {
                Label("Start fresh on this device", systemImage: "iphone")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var footnote: some View {
        Text("Anilite is an unofficial, non-commercial companion that uses the public AniList API. Artwork and data belong to their owners; streaming links go to official services.")
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
    }

    private func followProfile() {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !working else { return }
        working = true
        profileError = nil
        Task {
            do {
                try await model.usePublicProfile(name)
                Haptics.success()
            } catch {
                profileError = AppModel.message(for: error)
                Haptics.error()
            }
            working = false
        }
    }
}
