import SwiftUI
import AniliteKit

/// Full editor for one library entry: status, progress, score, dates, rewatches, notes,
/// and shelves. Changes are applied locally at once and synced in the background.
struct EntryEditorSheet: View {
    let media: Media

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var status: MediaListStatus = .planning
    @State private var progress = 0
    @State private var volumes = 0
    @State private var score: Double = 0
    @State private var repeats = 0
    @State private var notes = ""
    @State private var hasStart = false
    @State private var start = Date()
    @State private var hasFinish = false
    @State private var finish = Date()
    @State private var confirmRemove = false
    @State private var loaded = false

    private var existing: LibraryEntry? { model.entry(media.id) }
    private var total: Int? { media.totalUnits }
    private var tint: Color { Color(anilistHex: media.coverImage?.color) ?? Theme.brand }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        PosterImage(media: media, width: 52, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.title(media))
                                .font(.headline)
                                .lineLimit(2)
                            Text([media.formatLabel, total.map { "\($0) \(media.unitShort.lowercased())" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(MediaListStatus.allCases, id: \.self) { s in
                            Label(s.label(for: media.mediaType), systemImage: StatusDot.symbol(s)).tag(s)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Progress") {
                    Stepper(value: Binding(get: { progress }, set: { setProgress($0) }), in: 0...(total ?? 9_999)) {
                        HStack {
                            Text(media.mediaType == .anime ? "Episodes" : "Chapters")
                            Spacer()
                            Text(total.map { "\(progress) / \($0)" } ?? "\(progress)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                    }
                    if media.mediaType == .manga {
                        Stepper(value: $volumes, in: 0...(media.volumes ?? 999)) {
                            HStack {
                                Text("Volumes")
                                Spacer()
                                Text(media.volumes.map { "\(volumes) / \($0)" } ?? "\(volumes)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let total, progress < total {
                        Button("Mark all \(total) done") {
                            progress = total
                            status = .completed
                            Haptics.tap(.soft)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Score")
                            Spacer()
                            Text(model.scoreFormat.display(score))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(score > 0 ? tint : .secondary)
                        }
                        Slider(value: $score, in: 0...100, step: model.scoreFormat.step)
                            .tint(tint)
                            .accessibilityValue(score > 0 ? model.scoreFormat.display(score) : "Not scored")
                    }
                    if score > 0 {
                        Button("Clear score", role: .destructive) { score = 0 }
                    }
                } header: {
                    Text("Your score")
                } footer: {
                    Text("Shown in your AniList score format.")
                }

                Section("Dates") {
                    Toggle("Started", isOn: $hasStart.animation())
                    if hasStart {
                        DatePicker("Start date", selection: $start, in: ...Date(), displayedComponents: .date)
                    }
                    Toggle("Finished", isOn: $hasFinish.animation())
                    if hasFinish {
                        DatePicker("Finish date", selection: $finish, in: ...Date(), displayedComponents: .date)
                    }
                    Stepper("\(media.mediaType == .anime ? "Rewatched" : "Reread") \(repeats)×", value: $repeats, in: 0...99)
                }

                Section {
                    TextField("Private notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Notes")
                } footer: {
                    Text(model.account.isConnected ? "Notes sync to your AniList entry." : "Notes are saved with this library.")
                }

                let manual = model.allShelves.filter { !$0.isSmart }
                if !manual.isEmpty {
                    Section("Shelves") {
                        ForEach(manual) { shelf in
                            Button {
                                model.toggle(media.id, onShelf: shelf.id)
                                Haptics.tick()
                            } label: {
                                HStack {
                                    Label(shelf.name, systemImage: shelf.symbol)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if model.shelf(shelf.id)?.mediaIds.contains(media.id) == true {
                                        Image(systemName: "checkmark").foregroundStyle(tint)
                                    }
                                }
                            }
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Remove from library", role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink1.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add to library" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(!model.canEdit)
                }
            }
            .confirmationDialog("Remove \(model.title(media)) from your library?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.remove(mediaId: media.id)
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
    }

    /// Finishing every unit completes the entry; starting moves planning to current.
    private func setProgress(_ value: Int) {
        let old = progress
        progress = value
        if let total, total > 0, value >= total, old < total {
            status = .completed
        } else if value > 0, status == .planning {
            status = .current
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let entry = existing else {
            status = .planning
            return
        }
        status = entry.status
        progress = entry.progress
        volumes = entry.progressVolumes
        score = entry.score
        repeats = entry.repeatCount
        notes = entry.notes
        if let date = entry.startedAt?.date() { hasStart = true; start = date }
        if let date = entry.completedAt?.date() { hasFinish = true; finish = date }
    }

    private func save() {
        let change = EntryChange(
            mediaId: media.id,
            status: status,
            progress: progress,
            progressVolumes: media.mediaType == .manga ? volumes : nil,
            score: score,
            notes: notes,
            repeatCount: repeats,
            startedAt: hasStart ? FuzzyDate(date: start) : nil,
            completedAt: hasFinish ? FuzzyDate(date: finish) : nil
        )
        if model.save(change, media: media) { dismiss() }
    }
}

/// Quick diary note tied to the current point in a title.
struct JournalComposeSheet: View {
    let media: Media

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var feeling: JournalEntry.Feeling?
    @State private var attachUnit = true
    @FocusState private var focused: Bool

    private var unit: Int? {
        guard let progress = model.entry(media.id)?.progress, progress > 0 else { return nil }
        return progress
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        PosterImage(media: media, width: 40, cornerRadius: 6)
                        Text(model.title(media))
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "How did it feel?")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                            ForEach(JournalEntry.Feeling.allCases, id: \.self) { option in
                                Button {
                                    Haptics.tick()
                                    feeling = feeling == option ? nil : option
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(option.emoji).font(.title)
                                        Text(option.label)
                                            .font(Typo.micro)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 66)
                                    .background {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(feeling == option ? Theme.brand.opacity(0.3) : Color.white.opacity(0.05))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(feeling == option ? Theme.brand : Theme.hairline)
                                    }
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel(option.label)
                                .accessibilityAddTraits(feeling == option ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Note")
                        TextField("A moment, a theory, a favourite line…", text: $text, axis: .vertical)
                            .lineLimit(5...14)
                            .focused($focused)
                            .padding(14)
                            .glassSurface(cornerRadius: 16)
                    }

                    if let unit {
                        Toggle(isOn: $attachUnit) {
                            Text("Pin to \(media.unitName) \(unit)")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.brand)
                    }

                    Text("Journal notes stay on this device and are never posted to AniList.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(Theme.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.ink1.ignoresSafeArea())
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func save() {
        let entry = JournalEntry(
            mediaId: media.id,
            mediaTitle: model.title(media),
            coverURL: media.coverImage?.thumbnail,
            unit: attachUnit ? unit : nil,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            feeling: feeling
        )
        model.addJournal(entry)
        Haptics.success()
        dismiss()
    }
}
