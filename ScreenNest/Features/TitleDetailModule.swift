//  TitleDetailModule.swift
//  Screen Nest — one title.
//
//  Everything the house knows about it: the details, what it contains, the
//  content notes recorded here, the marks made while watching, the evenings it
//  appeared in, and — for a series — where you are up to.

import SwiftUI

final class TitleDetailPresenter: ObservableObject {
    @Published var showEditForm = false
    @Published var showNoteForm = false
    @Published var editingNote: ContentNote?
    @Published var toast: NestToast?
    @Published var confirmingArchive = false

    let titleId: UUID
    private let store: DataStore

    init(titleId: UUID, store: DataStore) {
        self.titleId = titleId
        self.store = store
    }

    var title: Title? { store.title(id: titleId) }
    var notes: [ContentNote] { store.notes(for: titleId) }
    var marks: [MarkedMoment] { store.previousMarks(forTitle: titleId) }
    var evenings: [Evening] {
        store.evenings(forTitle: titleId).sorted { $0.date > $1.date }
    }
    var watchCount: Int { store.watchCount(forTitle: titleId) }
    var country: RatingCountry { store.profile.ratingCountry }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct TitleDetailView: View {
    let titleId: UUID

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter: TitleDetailPresenter
    @Environment(\.presentationMode) private var presentationMode

    init(titleId: UUID) {
        self.titleId = titleId
        _presenter = StateObject(wrappedValue: TitleDetailPresenter(titleId: titleId, store: .shared))
    }

    var body: some View {
        ZStack {
            NestScreen(bottomInset: NestSpace.huge) {
                if let title = presenter.title {
                    header(title)
                    facts(title)
                    if !title.shortDescription.isEmpty { description(title) }
                    contentSection(title)
                    if title.type.isEpisodic { seriesSection(title) }
                    notesSection(title)
                    marksSection
                    historySection
                    actions(title)
                } else {
                    ErrorStateView(title: "Title not found",
                                   message: "It may have been deleted from the library.")
                }
            }
            ToastOverlay(toast: presenter.toast)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $presenter.showEditForm) {
            if let title = presenter.title {
                TitleFormView(title: title, prefill: nil) { saved in
                    store.upsertTitle(saved)
                    presenter.showEditForm = false
                    presenter.show(NestToast(message: "Changes saved"))
                } onCancel: {
                    presenter.showEditForm = false
                } onDelete: { id in
                    presenter.showEditForm = false
                    store.deleteTitle(id: id)
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .sheet(isPresented: $presenter.showNoteForm, onDismiss: { presenter.editingNote = nil }) {
            if let title = presenter.title {
                ContentNoteFormView(note: presenter.editingNote,
                                    title: title,
                                    viewers: store.viewers,
                                    onSave: { note in
                    store.upsertNote(note)
                    presenter.showNoteForm = false
                    presenter.show(NestToast(message: "Note saved"))
                }, onDelete: { id in
                    store.deleteNote(id: id)
                    presenter.showNoteForm = false
                }, onCancel: {
                    presenter.showNoteForm = false
                })
            }
        }
    }

    // MARK: Sections

    private func header(_ title: Title) -> some View {
        HStack(alignment: .top, spacing: NestSpace.l) {
            PosterView(title: title, width: 140, aspectRatio: 200.0 / 140.0)
                .nestGlow()
            VStack(alignment: .leading, spacing: NestSpace.s) {
                Text(title.name)
                    .font(NestFont.displaySmall)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !title.originalName.isEmpty, title.originalName != title.name {
                    Text(title.originalName)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkFaint)
                }
                HStack(spacing: NestSpace.s) {
                    Button {
                        NestHaptics.tap()
                        store.toggleFavourite(titleId: title.id)
                    } label: {
                        NestChip(title: title.isFavourite ? "Favourite" : "Mark Favourite",
                                 selected: title.isFavourite,
                                 tint: NestColor.amber)
                    }
                    .buttonStyle(.plain)
                }
                if presenter.watchCount > 0 {
                    Text("Watched \(presenter.watchCount) time\(presenter.watchCount == 1 ? "" : "s") here.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func facts(_ title: Title) -> some View {
        NestRowGroup {
            factRow("Type", title.type.title)
            RowDivider()
            factRow(title.type.isEpisodic ? "Episode runtime" : "Runtime", "\(title.runtimeMinutes) min")
            RowDivider()
            factRow("Release year", title.yearText)
            RowDivider()
            factRow("Genres", title.genres.isEmpty ? "—" : title.genres.joined(separator: ", "))
            RowDivider()
            certificationRow(title)
            RowDivider()
            factRow("Where to watch", title.whereToWatch.isEmpty ? "—" : title.whereToWatch)
            if !title.personalTags.isEmpty {
                RowDivider()
                factRow("Tags", title.personalTags.joined(separator: ", "))
            }
            if !title.privateNote.isEmpty {
                RowDivider()
                factRow("Private note", title.privateNote)
            }
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: NestSpace.m) {
            SectionLabel(label)
                .frame(width: 124, alignment: .leading)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(NestColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NestSpace.m)
        .frame(minHeight: 56)
    }

    private func certificationRow(_ title: Title) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: NestSpace.m) {
                SectionLabel("Certification")
                    .frame(width: 124, alignment: .leading)
                if let code = title.certification(for: presenter.country) {
                    HStack(spacing: NestSpace.s) {
                        nestTracked(code.uppercased(), kern: 0.6)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(NestColor.plum))
                        Text(presenter.country.bodyName)
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No certification for \(presenter.country.countryName)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(NestColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, NestSpace.m)
            .frame(minHeight: 56)
            if title.certification(for: presenter.country) == nil {
                Text("Decide for yourself, or add a content note.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.amberSunk)
                    .padding(.bottom, NestSpace.s)
            } else if let code = title.certification(for: presenter.country),
                      let cert = presenter.country.certification(code: code) {
                Text(cert.note)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, NestSpace.s)
            }
            if title.editedFields.contains("certification") {
                nestTracked("edited by you", kern: 0.8)
                    .font(NestFont.label)
                    .foregroundColor(NestColor.plum)
                    .padding(.bottom, NestSpace.s)
            }
        }
    }

    private func description(_ title: Title) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            SectionHead("What It Is About")
            NestCard {
                Text(title.shortDescription)
                    .font(NestFont.body)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func contentSection(_ title: Title) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title: "What Is In It", subtitle: nil) {
                NavigationLink(destination: SuitabilityView(titleId: title.id)) {
                    Text("Check It")
                        .font(NestFont.smallMedium)
                        .foregroundColor(NestColor.amberSunk)
                }
            }
            NestCard {
                if title.contentAspects.isEmpty && title.contentNotesText.isEmpty {
                    EmptyStateView(title: "No Content Details",
                                   message: "No content details for this title. Add what you know, or watch it yourself first.",
                                   primaryTitle: "Add What You Know",
                                   primaryAction: { presenter.showEditForm = true })
                } else {
                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        if !title.contentAspects.isEmpty {
                            ChipFlow(items: title.contentAspects) { aspect in
                                NestChip(title: aspect.title, selected: true,
                                         tint: NestColor.amber, glyph: aspect)
                            }
                        }
                        if !title.contentNotesText.isEmpty {
                            Text(title.contentNotesText)
                                .font(NestFont.body)
                                .foregroundColor(NestColor.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func seriesSection(_ title: Title) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title: "Series", subtitle: nil) {
                NavigationLink(destination: SeriesDetailView(titleId: title.id)) {
                    Text("Open")
                        .font(NestFont.smallMedium)
                        .foregroundColor(NestColor.amberSunk)
                }
            }
            NestCard {
                SeriesProgressPanel(title: title)
            }
        }
    }

    private func notesSection(_ title: Title) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title: "Content Notes", subtitle: "What actually happened in this house.") {
                Button("Add Note") {
                    presenter.editingNote = nil
                    presenter.showNoteForm = true
                }
                .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
            }
            if presenter.notes.isEmpty {
                NestCard {
                    EmptyStateView(title: "No Notes Yet",
                                   message: "After an evening, write down what happened and at what point. Notes marked “warn before watching” appear on the check.",
                                   primaryTitle: "Add Note",
                                   primaryAction: {
                        presenter.editingNote = nil
                        presenter.showNoteForm = true
                    })
                }
            } else {
                ForEach(presenter.notes) { note in
                    Button {
                        NestHaptics.tap()
                        presenter.editingNote = note
                        presenter.showNoteForm = true
                    } label: {
                        ContentNoteCard(note: note, viewers: store.viewers(ids: note.whoReacted))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var marksSection: some View {
        if !presenter.marks.isEmpty {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                SectionHead("Marked Moments", subtitle: "Made while watching, kept on the title.")
                NestCard {
                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        ForEach(presenter.marks) { mark in
                            HStack(spacing: NestSpace.m) {
                                Text(mark.timecode)
                                    .font(NestFont.figureSmall)
                                    .foregroundColor(NestColor.ink)
                                    .frame(width: 56, alignment: .leading)
                                NestChip(title: mark.kind.title,
                                         selected: mark.kind.isCautionary,
                                         tint: mark.kind.isCautionary ? NestColor.stop : NestColor.go)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !presenter.evenings.isEmpty {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                SectionHead("Evenings")
                ForEach(presenter.evenings) { evening in
                    NavigationLink(destination: EveningRecapView(eveningId: evening.id)) {
                        NestCard(padding: NestSpace.m) {
                            HStack(spacing: NestSpace.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(TimeFormat.dayFormatter.string(from: evening.date))
                                        .font(NestFont.bodyMedium)
                                        .foregroundColor(NestColor.ink)
                                    Text([evening.state.title, evening.outcome?.title]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(NestFont.small)
                                        .foregroundColor(NestColor.inkSoft)
                                }
                                Spacer()
                                ViewerTokenRow(viewers: store.viewers(ids: evening.viewerIds), size: 24)
                                Chevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actions(_ title: Title) -> some View {
        VStack(spacing: NestSpace.m) {
            MinuteTicks(count: 40, height: 5, emphasisEvery: 5, colour: NestColor.hairline)

            PrimaryButton(title: "Edit Title") { presenter.showEditForm = true }

            Button(title.isArchived ? "Restore from Archive" : "Archive Title") {
                NestHaptics.tap()
                store.setArchived(titleId: title.id, archived: !title.isArchived)
                presenter.show(NestToast(message: title.isArchived ? "Restored" : "Archived"))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, NestSpace.s)
    }
}

// MARK: - Shared pieces

struct ContentNoteCard: View {
    let note: ContentNote
    let viewers: [Viewer]

    var body: some View {
        NestCard(padding: NestSpace.m) {
            VStack(alignment: .leading, spacing: NestSpace.s) {
                HStack(spacing: NestSpace.s) {
                    if let timecode = note.timecode {
                        Text(timecode)
                            .font(NestFont.figureSmall)
                            .foregroundColor(NestColor.ink)
                    }
                    nestTracked(note.severity.title.lowercased(), kern: 0.7)
                        .font(NestFont.label)
                        .foregroundColor(severityColour)
                    Spacer()
                    if note.warnBeforeWatching {
                        nestTracked("warn before watching", kern: 0.7)
                            .font(NestFont.label)
                            .foregroundColor(NestColor.stop)
                    }
                }
                Text(note.whatHappens)
                    .font(NestFont.body)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if !note.adviceNextTime.isEmpty {
                    Text(note.adviceNextTime)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                if !viewers.isEmpty {
                    ViewerTokenRow(viewers: viewers, size: 22)
                }
            }
        }
    }

    private var severityColour: Color {
        switch note.severity {
        case .mild: return NestColor.go
        case .notable: return NestColor.amberSunk
        case .strong: return NestColor.stop
        }
    }
}

struct SeriesProgressPanel: View {
    let title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            let position = title.seriesPosition ?? SeriesPosition()
            let total = max(1, title.episodeCount)
            let watched = total - title.episodesLeft

            HStack(alignment: .firstTextBaseline) {
                Text("Season \(position.seasonNumber)")
                    .font(NestFont.titleTight)
                    .foregroundColor(NestColor.ink)
                Spacer()
                Text("\(watched) of \(total)")
                    .font(NestFont.figureSmall)
                    .foregroundColor(NestColor.inkSoft)
            }
            WindowBar(fraction: Double(watched) / Double(total), height: 10, showTicks: false)

            if let next = title.nextEpisode {
                Text("Next: S\(next.season) · E\(next.episode.number) — \(next.episode.name) (\(next.episode.runtimeMinutes) min)")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if title.episodeCount > 0 {
                Text("Finished — every episode is marked watched.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.go)
            } else {
                Text("No episodes recorded yet. Add seasons when you edit the title, or search online.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
