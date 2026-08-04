//  ContentNotesModule.swift
//  Screen Nest — content notes.
//
//  Observations about this family, not somebody else's description of a film.
//  A note with "warn before watching" on appears at the top of the check.

import SwiftUI

// MARK: - Form

final class ContentNoteFormPresenter: ObservableObject {
    @Published var hasTimestamp: Bool
    @Published var minutes: Int
    @Published var seconds: Int
    @Published var whatHappens: String
    @Published var whoReacted: Set<UUID>
    @Published var severity: NoteSeverity
    @Published var advice: String
    @Published var warnBefore: Bool

    @Published var attemptedSave = false
    @Published var isSaving = false
    @Published var confirmingDelete = false

    private let original: ContentNote?
    let titleId: UUID
    let titleName: String

    init(note: ContentNote?, title: Title) {
        original = note
        titleId = title.id
        titleName = title.name
        hasTimestamp = note?.timestampSeconds != nil
        minutes = (note?.timestampSeconds ?? 0) / 60
        seconds = (note?.timestampSeconds ?? 0) % 60
        whatHappens = note?.whatHappens ?? ""
        whoReacted = Set(note?.whoReacted ?? [])
        severity = note?.severity ?? .notable
        advice = note?.adviceNextTime ?? ""
        warnBefore = note?.warnBeforeWatching ?? true
    }

    var isEditing: Bool { original != nil }
    var noteId: UUID? { original?.id }

    var whatError: String? {
        guard attemptedSave else { return nil }
        return whatHappens.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Write down what happens — that is the whole note."
            : nil
    }

    var isValid: Bool { !whatHappens.trimmingCharacters(in: .whitespaces).isEmpty }

    func build() -> ContentNote {
        var note = original ?? ContentNote(titleId: titleId)
        note.titleId = titleId
        note.titleName = titleName
        note.timestampSeconds = hasTimestamp ? (minutes * 60 + seconds) : nil
        note.whatHappens = whatHappens.trimmingCharacters(in: .whitespaces)
        note.whoReacted = Array(whoReacted)
        note.severity = severity
        note.adviceNextTime = advice
        note.warnBeforeWatching = warnBefore
        return note
    }
}

struct ContentNoteFormView: View {
    @StateObject private var presenter: ContentNoteFormPresenter
    let viewers: [Viewer]
    let onSave: (ContentNote) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    init(note: ContentNote?,
         title: Title,
         viewers: [Viewer],
         onSave: @escaping (ContentNote) -> Void,
         onDelete: @escaping (UUID) -> Void,
         onCancel: @escaping () -> Void) {
        _presenter = StateObject(wrappedValue: ContentNoteFormPresenter(note: note, title: title))
        self.viewers = viewers
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        SheetScaffold(title: presenter.isEditing ? "Edit Note" : "Add Note",
                      subtitle: presenter.titleName,
                      closeTitle: "Cancel",
                      onClose: onCancel) {

            FieldShell(label: "Timestamp", hint: "Where in the film it happens.") {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    NestToggleRow(title: "Note a point in the film", isOn: $presenter.hasTimestamp)
                    if presenter.hasTimestamp {
                        HStack(spacing: NestSpace.m) {
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel("minutes")
                                NestStepper(value: $presenter.minutes, range: 0...600, step: 1, suffix: "min")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel("seconds")
                                NestStepper(value: $presenter.seconds, range: 0...59, step: 5, suffix: "sec")
                            }
                        }
                        Text("Shows as \(TimeFormat.clock(seconds: presenter.minutes * 60 + presenter.seconds)).")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkFaint)
                    }
                }
            }

            FieldShell(label: "What Happens", error: presenter.whatError, required: true) {
                NestTextArea(placeholder: "e.g. The dog is hurt and the boy cries.",
                             text: $presenter.whatHappens,
                             minHeight: 84,
                             invalid: presenter.whatError != nil)
            }

            FieldShell(label: "Who Reacted") {
                if viewers.isEmpty {
                    Text("No viewers to attach yet.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkFaint)
                } else {
                    ChipFlow(items: viewers) { viewer in
                        NestChip(title: viewer.name,
                                 selected: presenter.whoReacted.contains(viewer.id),
                                 tint: NestColor.viewerHue(viewer.colourIndex)) {
                            if presenter.whoReacted.contains(viewer.id) {
                                presenter.whoReacted.remove(viewer.id)
                            } else {
                                presenter.whoReacted.insert(viewer.id)
                            }
                        }
                    }
                }
            }

            FieldShell(label: "Severity") {
                NestSegmented(options: NoteSeverity.allCases,
                              selection: $presenter.severity,
                              titleFor: { $0.title })
            }

            FieldShell(label: "Advice for Next Time") {
                NestTextArea(placeholder: "e.g. Say beforehand that the dog is fine at the end.",
                             text: $presenter.advice, minHeight: 70)
            }

            FieldShell(label: "Warn Before Watching",
                       hint: "On: this note appears at the top of the suitability check for this title.") {
                NestToggleRow(title: "Show this before we watch it again", isOn: $presenter.warnBefore)
            }

            VStack(spacing: NestSpace.m) {
                PrimaryButton(title: presenter.isEditing ? "Save Note" : "Add Note",
                              busy: presenter.isSaving) {
                    presenter.attemptedSave = true
                    guard presenter.isValid else {
                        NestHaptics.warning()
                        return
                    }
                    presenter.isSaving = true
                    NestHaptics.success()
                    onSave(presenter.build())
                }

                if let id = presenter.noteId {
                    Button("Delete Note") {
                        NestHaptics.tap()
                        presenter.confirmingDelete = true
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: NestColor.stop))
                    .alert("Delete this note?", isPresented: $presenter.confirmingDelete) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete", role: .destructive) { onDelete(id) }
                    }
                }
            }
            .padding(.top, NestSpace.s)
        }
    }
}

// MARK: - All notes

final class ContentNotesPresenter: ObservableObject {
    @Published var search: String = ""
    @Published var onlyWarnings = false
    @Published var editing: ContentNote?
    @Published var showForm = false
    @Published var pickingTitle = false

    private let store: DataStore
    init(store: DataStore) { self.store = store }

    var notes: [ContentNote] {
        store.contentNotes
            .filter { note in
                if onlyWarnings && !note.warnBeforeWatching { return false }
                let query = search.trimmingCharacters(in: .whitespaces)
                guard !query.isEmpty else { return true }
                return note.whatHappens.localizedCaseInsensitiveContains(query)
                    || note.titleName.localizedCaseInsensitiveContains(query)
                    || note.adviceNextTime.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                if lhs.titleName == rhs.titleName {
                    return (lhs.timestampSeconds ?? 0) < (rhs.timestampSeconds ?? 0)
                }
                return lhs.titleName < rhs.titleName
            }
    }

    /// Marks made in Watch Mode that have not been turned into a note yet.
    var unconvertedMarks: [(evening: Evening, mark: MarkedMoment, title: Title?)] {
        var out: [(Evening, MarkedMoment, Title?)] = []
        for evening in store.evenings where !evening.watch.marks.isEmpty {
            let title = store.title(id: evening.titleId)
            for mark in evening.watch.marks where mark.kind.isCautionary {
                let alreadyNoted = store.contentNotes.contains {
                    $0.titleId == evening.titleId && $0.timestampSeconds == mark.atSeconds
                }
                if !alreadyNoted { out.append((evening, mark, title)) }
            }
        }
        return out.sorted { $0.0.date > $1.0.date }
    }

    func titles() -> [Title] { store.activeTitles.sorted { $0.name < $1.name } }
}

struct ContentNotesView: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter = ContentNotesPresenter(store: .shared)
    @State private var pendingTitle: Title?

    var body: some View {
        NestScreen(bottomInset: NestSpace.huge) {
            PageTitle(title: "Content Notes",
                      subtitle: "What happened in this house, at what point, and what to say next time.")

            NestSearchField(placeholder: "Search notes", text: $presenter.search)

            NestSegmented(options: [false, true],
                          selection: $presenter.onlyWarnings,
                          titleFor: { $0 ? "Warn Before Watching" : "All Notes" })

            if !presenter.unconvertedMarks.isEmpty {
                fromMarkedMoments
            }

            if presenter.notes.isEmpty {
                NestCard {
                    EmptyStateView(
                        title: presenter.search.isEmpty ? "No Notes Yet" : "Nothing Matches",
                        message: presenter.search.isEmpty
                            ? "After an evening, write down what actually happened. Over time this becomes more accurate about your children than any outside guide."
                            : "No note matches that search.",
                        primaryTitle: store.activeTitles.isEmpty ? nil : "Add Note",
                        primaryAction: store.activeTitles.isEmpty ? nil : { presenter.pickingTitle = true }
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    ForEach(presenter.notes) { note in
                        Button {
                            NestHaptics.tap()
                            pendingTitle = store.title(id: note.titleId)
                            presenter.editing = note
                            presenter.showForm = pendingTitle != nil
                        } label: {
                            VStack(alignment: .leading, spacing: NestSpace.xs) {
                                Text(note.titleName)
                                    .font(NestFont.smallMedium)
                                    .foregroundColor(NestColor.inkFaint)
                                ContentNoteCard(note: note, viewers: store.viewers(ids: note.whoReacted))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Add Note") { presenter.pickingTitle = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $presenter.showForm, onDismiss: {
            presenter.editing = nil
            pendingTitle = nil
        }) {
            if let title = pendingTitle {
                ContentNoteFormView(note: presenter.editing,
                                    title: title,
                                    viewers: store.viewers,
                                    onSave: { note in
                    store.upsertNote(note)
                    presenter.showForm = false
                }, onDelete: { id in
                    store.deleteNote(id: id)
                    presenter.showForm = false
                }, onCancel: {
                    presenter.showForm = false
                })
            }
        }
        .sheet(isPresented: $presenter.pickingTitle) {
            TitlePickerSheet(titles: presenter.titles()) { title in
                presenter.pickingTitle = false
                pendingTitle = title
                presenter.editing = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presenter.showForm = true
                }
            } onCancel: {
                presenter.pickingTitle = false
            }
        }
    }

    private var fromMarkedMoments: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("From Marked Moments",
                        subtitle: "Marks made while watching that have not become notes yet.")
            ForEach(Array(presenter.unconvertedMarks.enumerated()), id: \.offset) { _, entry in
                Button {
                    guard let title = entry.title else { return }
                    NestHaptics.tap()
                    pendingTitle = title
                    presenter.editing = ContentNote(titleId: title.id,
                                                    titleName: title.name,
                                                    timestampSeconds: entry.mark.atSeconds,
                                                    whatHappens: "",
                                                    whoReacted: entry.evening.viewerIds,
                                                    severity: entry.mark.kind == .scary ? .strong : .notable,
                                                    warnBeforeWatching: true)
                    presenter.showForm = true
                } label: {
                    NestCard(padding: NestSpace.m) {
                        HStack(spacing: NestSpace.m) {
                            Text(entry.mark.timecode)
                                .font(NestFont.figureSmall)
                                .foregroundColor(NestColor.ink)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.title?.name ?? entry.evening.displayName)
                                    .font(NestFont.bodyMedium)
                                    .foregroundColor(NestColor.ink)
                                Text("\(entry.mark.kind.title) · \(TimeFormat.shortDayFormatter.string(from: entry.evening.date))")
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkSoft)
                            }
                            Spacer()
                            Text("Make a note")
                                .font(NestFont.smallMedium)
                                .foregroundColor(NestColor.amberSunk)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(entry.title == nil)
            }
        }
    }
}

// MARK: - Title picker

struct TitlePickerSheet: View {
    let titles: [Title]
    let onPick: (Title) -> Void
    let onCancel: () -> Void

    @State private var search = ""

    var body: some View {
        SheetScaffold(title: "Choose a Title", closeTitle: "Cancel", onClose: onCancel) {
            NestSearchField(placeholder: "Search Titles", text: $search)

            let filtered = search.trimmingCharacters(in: .whitespaces).isEmpty
                ? titles
                : titles.filter { $0.name.localizedCaseInsensitiveContains(search) }

            if filtered.isEmpty {
                NestCard {
                    EmptyStateView(title: "Nothing Here",
                                   message: titles.isEmpty
                                    ? "The library is empty. Add a title first."
                                    : "No title matches that search.")
                }
            } else {
                ForEach(filtered) { title in
                    Button {
                        NestHaptics.tap()
                        onPick(title)
                    } label: {
                        NestCard(padding: NestSpace.m) {
                            HStack(spacing: NestSpace.m) {
                                PosterView(title: title, width: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title.name)
                                        .font(NestFont.bodyMedium)
                                        .foregroundColor(NestColor.ink)
                                        .multilineTextAlignment(.leading)
                                    Text("\(title.type.title) · \(title.runtimeMinutes) min")
                                        .font(NestFont.small)
                                        .foregroundColor(NestColor.inkSoft)
                                }
                                Spacer()
                                Chevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
