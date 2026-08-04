//  LibraryModule.swift
//  Screen Nest — the library.
//
//  One source of truth for every evening. Sections are computed from the real
//  suitability check, not from a stored label, so "Fits Everyone" means it fits
//  the people in this house tonight.

import SwiftUI

// MARK: - Entities

enum LibrarySection: String, CaseIterable, Identifiable {
    case all, fitsEveryone, fitsOlderOnly, notYet, watched, favourites, seriesInProgress, archived
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Titles"
        case .fitsEveryone: return "Fits Everyone"
        case .fitsOlderOnly: return "Fits Older Only"
        case .notYet: return "Not Yet"
        case .watched: return "Watched"
        case .favourites: return "Favourites"
        case .seriesInProgress: return "Series in Progress"
        case .archived: return "Archived"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "Add a few titles and the app can start working out what fits."
        case .fitsEveryone: return "Nothing in the library clears everyone tonight. The reasons are on each title."
        case .fitsOlderOnly: return "Nothing here is fine for the older ones only."
        case .notYet: return "Nothing is held back by age or content right now."
        case .watched: return "No evening has been completed yet."
        case .favourites: return "Mark a title as a favourite and it appears here."
        case .seriesInProgress: return "No series has been started."
        case .archived: return "Nothing has been archived."
        }
    }
}

enum WatchStatusFilter: String, CaseIterable, Identifiable {
    case any, watched, notWatched
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: return "Any"
        case .watched: return "Watched"
        case .notWatched: return "Not Watched"
        }
    }
}

struct LibraryFilters {
    var search: String = ""
    var type: ContentType?
    var genre: String?
    var maxRuntime: Int?
    var certification: String?
    var fitsViewerId: UUID?
    var whereToWatch: String?
    var watchStatus: WatchStatusFilter = .any

    var isActive: Bool {
        type != nil || genre != nil || maxRuntime != nil || certification != nil
            || fitsViewerId != nil || whereToWatch != nil || watchStatus != .any
    }

    var count: Int {
        [type != nil, genre != nil, maxRuntime != nil, certification != nil,
         fitsViewerId != nil, whereToWatch != nil, watchStatus != .any]
            .filter { $0 }.count
    }
}

struct LibraryEntry: Identifiable {
    var id: UUID { title.id }
    let title: Title
    let result: SuitabilityResult
    let watchCount: Int
}

// MARK: - Interactor

protocol LibraryInteracting {
    func entries(section: LibrarySection, filters: LibraryFilters) -> [LibraryEntry]
    var whereToWatchOptions: [String] { get }
    var genreOptions: [String] { get }
}

struct LibraryInteractor: LibraryInteracting {
    let store: DataStore

    var whereToWatchOptions: [String] {
        Array(Set(store.titles.map { $0.whereToWatch.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })).sorted()
    }

    var genreOptions: [String] {
        let used = Set(store.titles.flatMap(\.genres))
        return Array(used.union(GenreCatalogue.all)).sorted()
    }

    func entries(section: LibrarySection, filters: LibraryFilters) -> [LibraryEntry] {
        let service = SuitabilityService(store: store)
        let viewers = filters.fitsViewerId.flatMap { id in store.viewer(id: id).map { [$0] } } ?? store.viewers
        let window = service.window(for: viewers)

        let pool = section == .archived ? store.titles.filter(\.isArchived) : store.titles.filter { !$0.isArchived }

        var entries = pool.map { title -> LibraryEntry in
            let runtime = title.type.isEpisodic ? (title.nextEpisode?.episode.runtimeMinutes ?? title.runtimeMinutes) : nil
            let result = service.evaluate(title: title, viewers: viewers, window: window, runtimeOverride: runtime)
            return LibraryEntry(title: title, result: result, watchCount: store.watchCount(forTitle: title.id))
        }

        entries = entries.filter { entry in matches(entry, section: section, filters: filters) }

        return entries.sorted { lhs, rhs in
            if section == .all || section == .archived {
                return lhs.title.name.localizedCaseInsensitiveCompare(rhs.title.name) == .orderedAscending
            }
            if lhs.result.status.rank != rhs.result.status.rank {
                return lhs.result.status.rank < rhs.result.status.rank
            }
            return lhs.title.name.localizedCaseInsensitiveCompare(rhs.title.name) == .orderedAscending
        }
    }

    private func matches(_ entry: LibraryEntry, section: LibrarySection, filters: LibraryFilters) -> Bool {
        let title = entry.title

        switch section {
        case .all, .archived: break
        case .fitsEveryone: if entry.result.status != .fitsEveryone { return false }
        case .fitsOlderOnly: if entry.result.status != .fitsOlderOnly { return false }
        case .notYet: if entry.result.status != .notYet { return false }
        case .watched: if entry.watchCount == 0 { return false }
        case .favourites: if !title.isFavourite { return false }
        case .seriesInProgress:
            guard title.type.isEpisodic,
                  let position = title.seriesPosition,
                  position.episodeNumber > 0 || position.seasonNumber > 1,
                  title.episodesLeft > 0 else { return false }
        }

        let query = filters.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let haystack = ([title.name, title.originalName, title.shortDescription, title.whereToWatch]
                            + title.genres + title.personalTags).joined(separator: " ")
            if !haystack.localizedCaseInsensitiveContains(query) { return false }
        }
        if let type = filters.type, title.type != type { return false }
        if let genre = filters.genre, !title.genres.contains(genre) { return false }
        if let maxRuntime = filters.maxRuntime, title.runtimeMinutes > maxRuntime { return false }
        if let certification = filters.certification {
            guard title.certification(for: store.profile.ratingCountry) == certification else { return false }
        }
        if let place = filters.whereToWatch,
           title.whereToWatch.trimmingCharacters(in: .whitespaces) != place { return false }
        switch filters.watchStatus {
        case .any: break
        case .watched: if entry.watchCount == 0 { return false }
        case .notWatched: if entry.watchCount > 0 { return false }
        }
        return true
    }
}

// MARK: - Presenter

final class LibraryPresenter: ObservableObject {
    @Published var section: LibrarySection = .all
    @Published var filters = LibraryFilters()
    @Published private(set) var entries: [LibraryEntry] = []
    @Published var showFilters = false
    @Published var showAddChoice = false
    @Published var showManualForm = false
    @Published var showOnlineSearch = false
    /// Details brought back from an online search, waiting for the form to open.
    @Published var pendingPrefill: TitlePrefill?
    @Published var toast: NestToast?

    private let interactor: LibraryInteracting

    init(interactor: LibraryInteracting) {
        self.interactor = interactor
        refresh()
    }

    func refresh() {
        entries = interactor.entries(section: section, filters: filters)
    }

    var whereToWatchOptions: [String] { interactor.whereToWatchOptions }
    var genreOptions: [String] { interactor.genreOptions }

    func clearFilters() {
        filters = LibraryFilters(search: filters.search)
        refresh()
    }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

// MARK: - View

struct LibraryView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter = LibraryPresenter(interactor: LibraryInteractor(store: .shared))
    @AppStorage(NestDefaults.showPosters) private var showPosters: Bool = true

    var body: some View {
        NavigationView {
            ZStack {
                NestScreen {
                    header
                    sectionPicker
                    content
                }
                ToastOverlay(toast: presenter.toast)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            presenter.refresh()
            if router.libraryOpensAddForm {
                router.libraryOpensAddForm = false
                presenter.showAddChoice = true
            }
        }
        .onReceive(store.$document.dropFirst()) { _ in presenter.refresh() }
        .onChange(of: router.libraryOpensAddForm) { open in
            if open {
                router.libraryOpensAddForm = false
                presenter.showAddChoice = true
            }
        }
        .confirmationDialog("Add a title", isPresented: $presenter.showAddChoice, titleVisibility: .visible) {
            Button("Search Online") { presenter.showOnlineSearch = true }
            Button("Add by Hand") { presenter.showManualForm = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Search fills the details in for you. Adding by hand always works, with or without a connection.")
        }
        .sheet(isPresented: $presenter.showManualForm, onDismiss: { presenter.pendingPrefill = nil }) {
            TitleFormView(title: nil, prefill: presenter.pendingPrefill) { saved in
                store.upsertTitle(saved)
                presenter.showManualForm = false
                presenter.refresh()
                presenter.show(NestToast(message: "Title Saved"))
            } onCancel: {
                presenter.showManualForm = false
            } onDelete: { _ in
                presenter.showManualForm = false
            }
        }
        .sheet(isPresented: $presenter.showOnlineSearch) {
            OnlineSearchView { prefill in
                presenter.showOnlineSearch = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presenter.pendingPrefill = prefill
                    presenter.showManualForm = true
                }
            } onCancel: {
                presenter.showOnlineSearch = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            HStack(alignment: .top) {
                PageTitle(title: "Library",
                          subtitle: "\(store.activeTitles.count) title\(store.activeTitles.count == 1 ? "" : "s") in this house")
                Spacer()
                Button {
                    NestHaptics.tap()
                    presenter.showAddChoice = true
                } label: {
                    ZStack {
                        Circle().fill(NestColor.amberGradient).frame(width: 60, height: 60)
                            .nestGlow()
                        Text("+")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundColor(NestColor.inkOnAmber)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add title")
            }

            HStack(spacing: NestSpace.s) {
                NestSearchField(placeholder: "Search Titles", text: Binding(
                    get: { presenter.filters.search },
                    set: { presenter.filters.search = $0; presenter.refresh() }
                ))
                Button {
                    NestHaptics.tap()
                    presenter.showFilters = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                            .fill(presenter.filters.isActive
                                  ? AnyShapeStyle(NestColor.amberGradient)
                                  : AnyShapeStyle(NestColor.surface))
                            .frame(width: 52, height: 52)
                            .nestGlowTight()
                        RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                            .stroke(NestColor.border, lineWidth: NestStroke.hair)
                            .frame(width: 52, height: 52)
                        VStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { index in
                                Capsule()
                                    .fill(presenter.filters.isActive ? NestColor.inkOnAmber : NestColor.ink)
                                    .frame(width: index == 1 ? 12 : 20, height: 2)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter")
            }

            if presenter.filters.isActive {
                HStack(spacing: NestSpace.s) {
                    Text("\(presenter.filters.count) filter\(presenter.filters.count == 1 ? "" : "s") on")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                    Spacer()
                    Button("Clear Filters") { presenter.clearFilters() }
                        .buttonStyle(QuietButtonStyle(tint: NestColor.stop))
                }
            }
        }
        .sheet(isPresented: $presenter.showFilters) {
            LibraryFiltersView(filters: $presenter.filters,
                               genres: presenter.genreOptions,
                               places: presenter.whereToWatchOptions,
                               country: store.profile.ratingCountry,
                               viewers: store.viewers) {
                presenter.showFilters = false
                presenter.refresh()
            } onClear: {
                presenter.clearFilters()
            }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NestSpace.s) {
                ForEach(LibrarySection.allCases) { section in
                    NestChip(title: section.title,
                             selected: presenter.section == section) {
                        withAnimation(NestMotion.snap) {
                            presenter.section = section
                            presenter.refresh()
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.isLoaded {
            LoadingStateView(message: "Opening the library…")
        } else if let error = store.loadError {
            ErrorStateView(title: "The library could not be read", message: error, retryTitle: "Reload") {
                store.load()
                presenter.refresh()
            }
        } else if presenter.entries.isEmpty {
            NestCard {
                EmptyStateView(
                    title: store.titles.isEmpty ? "Nothing to Watch Yet" : "Nothing in \(presenter.section.title)",
                    message: store.titles.isEmpty
                        ? "Add a few films and the app will work out which ones fit tonight, and which ones fit this child."
                        : presenter.section.emptyMessage,
                    primaryTitle: store.titles.isEmpty ? "Add Title" : nil,
                    primaryAction: store.titles.isEmpty ? { presenter.showAddChoice = true } : nil,
                    secondaryTitle: presenter.filters.isActive ? "Clear Filters" : nil,
                    secondaryAction: presenter.filters.isActive ? { presenter.clearFilters() } : nil
                )
            }
        } else {
            LazyVStack(spacing: NestSpace.m) {
                if presenter.section == .seriesInProgress {
                    NavigationLink(destination: SeriesListView()) {
                        NestRow(title: "All Series",
                                subtitle: "Every series, with where you are up to and whether the next episode fits tonight",
                                trailing: { Chevron() }, action: nil)
                            .padding(.horizontal, NestSpace.l)
                            .background(
                                RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                                    .fill(NestColor.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                                    .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
                            )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(Array(presenter.entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(destination: TitleDetailView(titleId: entry.title.id)) {
                        LibraryRow(entry: entry, showPoster: showPosters)
                    }
                    .buttonStyle(.plain)
                    .nestRise(index)
                }
            }
        }
    }
}

// MARK: - Row

struct LibraryRow: View {
    let entry: LibraryEntry
    var showPoster: Bool = true

    var body: some View {
        TicketCard(padding: NestSpace.m) {
            HStack(alignment: .top, spacing: NestSpace.m) {
                PosterView(title: entry.title, width: 72, showPoster: showPoster)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        Text(entry.title.name)
                            .font(NestFont.titleTight)
                            .foregroundColor(NestColor.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: NestSpace.xs)
                        if entry.title.isFavourite {
                            Circle().fill(NestColor.amber).frame(width: 10, height: 10).padding(.top, 6)
                        }
                    }

                    Text(subtitle)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)

                    HStack(spacing: NestSpace.s) {
                        StatusPill(status: entry.result.status, compact: true)
                        if entry.watchCount > 0 {
                            Text("watched \(entry.watchCount)×")
                                .font(NestFont.micro)
                                .foregroundColor(NestColor.inkFaint)
                        }
                        Spacer(minLength: 0)
                    }

                    if !entry.title.contentAspects.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(entry.title.contentAspects.prefix(7), id: \.self) { aspect in
                                AspectGlyph(aspect: aspect, size: 18, tint: NestColor.inkSoft, lineWidth: 2)
                            }
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [entry.title.type.title]
        if entry.title.runtimeMinutes > 0 { parts.append("\(entry.title.runtimeMinutes) min") }
        if let year = entry.title.releaseYear { parts.append("\(year)") }
        if !entry.title.genres.isEmpty { parts.append(entry.title.genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Filters sheet

struct LibraryFiltersView: View {
    @Binding var filters: LibraryFilters
    let genres: [String]
    let places: [String]
    let country: RatingCountry
    let viewers: [Viewer]
    let onApply: () -> Void
    let onClear: () -> Void

    var body: some View {
        SheetScaffold(title: "Filter", subtitle: "Everything here narrows the list you are looking at.",
                      closeTitle: "Done", onClose: onApply) {

            FieldShell(label: "Type") {
                ChipFlow(items: ContentType.allCases) { type in
                    NestChip(title: type.title, selected: filters.type == type) {
                        filters.type = filters.type == type ? nil : type
                    }
                }
            }

            FieldShell(label: "Genre") {
                ChipFlow(items: genres) { genre in
                    NestChip(title: genre, selected: filters.genre == genre) {
                        filters.genre = filters.genre == genre ? nil : genre
                    }
                }
            }

            FieldShell(label: "Runtime", hint: "Show titles no longer than this.") {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    NestToggleRow(title: "Limit running time",
                                  isOn: Binding(
                                    get: { filters.maxRuntime != nil },
                                    set: { filters.maxRuntime = $0 ? 90 : nil }
                                  ))
                    if filters.maxRuntime != nil {
                        NestSlider(value: Binding(
                            get: { filters.maxRuntime ?? 90 },
                            set: { filters.maxRuntime = $0 }
                        ), range: 10...240, step: 5, suffix: "min or less")
                    }
                }
            }

            FieldShell(label: "Certification", hint: country.displayName) {
                ChipFlow(items: country.certifications.map(\.code)) { code in
                    NestChip(title: code, selected: filters.certification == code) {
                        filters.certification = filters.certification == code ? nil : code
                    }
                }
            }

            if !viewers.isEmpty {
                FieldShell(label: "Fits Viewer", hint: "Check the whole library against one person.") {
                    ChipFlow(items: viewers) { viewer in
                        NestChip(title: viewer.name,
                                 selected: filters.fitsViewerId == viewer.id,
                                 tint: NestColor.viewerHue(viewer.colourIndex)) {
                            filters.fitsViewerId = filters.fitsViewerId == viewer.id ? nil : viewer.id
                        }
                    }
                }
            }

            if !places.isEmpty {
                FieldShell(label: "Where to Watch") {
                    ChipFlow(items: places) { place in
                        NestChip(title: place, selected: filters.whereToWatch == place) {
                            filters.whereToWatch = filters.whereToWatch == place ? nil : place
                        }
                    }
                }
            }

            FieldShell(label: "Watch Status") {
                NestSegmented(options: WatchStatusFilter.allCases,
                              selection: $filters.watchStatus,
                              titleFor: { $0.title })
            }

            VStack(spacing: NestSpace.m) {
                PrimaryButton(title: "Show Results") { onApply() }
                Button("Clear Filters") {
                    onClear()
                    onApply()
                }
                .buttonStyle(SecondaryButtonStyle(tint: NestColor.stop))
            }
            .padding(.top, NestSpace.s)
        }
    }
}
