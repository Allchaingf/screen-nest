//  EveningsModule.swift
//  Screen Nest — planned evenings and the history.
//
//  Completed evenings are read-only. "Watch Again" makes a new evening with a
//  new date and its own identity; it never edits the old one.

import SwiftUI

enum EveningsScope: String, CaseIterable, Identifiable {
    case upcoming, history
    var id: String { rawValue }
    var title: String { self == .upcoming ? "Planned" : "History" }
}

final class EveningsPresenter: ObservableObject {
    @Published var scope: EveningsScope = .upcoming
    @Published var search: String = ""
    @Published var filterViewerId: UUID?
    @Published var filterOutcome: EveningOutcome?
    @Published var showWizard = false
    @Published var toast: NestToast?

    private let store: DataStore
    init(store: DataStore) { self.store = store }

    var draft: Evening? { store.draftEvening }
    var inProgress: Evening? { store.unfinishedEvening }

    var upcoming: [Evening] {
        store.evenings
            .filter { $0.state == .planned || $0.state == .watching || $0.state == .awaitingReactions }
            .sorted { $0.date < $1.date }
    }

    var history: [Evening] {
        store.completedEvenings.filter { evening in
            if let viewerId = filterViewerId, !evening.viewerIds.contains(viewerId) { return false }
            if let outcome = filterOutcome, evening.outcome != outcome { return false }
            let query = search.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return true }
            return (evening.titleSnapshot?.name ?? "").localizedCaseInsensitiveContains(query)
                || evening.displayName.localizedCaseInsensitiveContains(query)
                || evening.parentNote.localizedCaseInsensitiveContains(query)
        }
    }

    /// History grouped by day, newest first.
    var historyGroups: [(day: Date, evenings: [Evening])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]?.sorted { $0.date > $1.date } ?? []) }
    }

    var viewers: [Viewer] { store.viewers }

    func viewers(for evening: Evening) -> [Viewer] { store.viewers(ids: evening.viewerIds) }

    func watchAgain(_ evening: Evening) -> Evening {
        var fresh = Evening()
        fresh.name = evening.name
        fresh.date = Date()
        fresh.startTime = evening.startTime
        fresh.occasion = evening.occasion
        fresh.viewerIds = evening.viewerIds
        fresh.window = store.profile.defaultWindow(on: Date())
        fresh.titleId = evening.titleId
        fresh.titleSnapshot = evening.titleSnapshot
        fresh.episodeRef = evening.episodeRef
        fresh.state = .planned
        fresh.planningStartedAt = Date()
        store.upsertEvening(fresh)
        NotificationService.shared.reschedule(for: store.document)
        return fresh
    }

    func clearFilters() {
        filterViewerId = nil
        filterOutcome = nil
        search = ""
    }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct EveningsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter = EveningsPresenter(store: .shared)

    var body: some View {
        NavigationView {
            ZStack {
                NestScreen {
                    header
                    NestSegmented(options: EveningsScope.allCases,
                                  selection: $presenter.scope,
                                  titleFor: { $0.title })

                    if !store.isLoaded {
                        LoadingStateView(message: "Reading your evenings…")
                    } else if let error = store.loadError {
                        ErrorStateView(title: "Could not read your evenings",
                                       message: error, retryTitle: "Reload") { store.load() }
                    } else if presenter.scope == .upcoming {
                        upcomingContent
                    } else {
                        historyContent
                    }
                }
                ToastOverlay(toast: presenter.toast)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if router.eveningsOpensWizard {
                router.eveningsOpensWizard = false
                presenter.showWizard = true
            }
        }
        .onChange(of: router.eveningsOpensWizard) { open in
            if open {
                router.eveningsOpensWizard = false
                presenter.showWizard = true
            }
        }
        .sheet(isPresented: $presenter.showWizard) {
            EveningWizardView {
                presenter.showWizard = false
                presenter.show(NestToast(message: "Evening created"))
            } onCancel: {
                presenter.showWizard = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageTitle(title: "Evenings",
                      subtitle: "Planned, in progress and everything that already happened.")
            Spacer()
            Button {
                NestHaptics.tap()
                presenter.showWizard = true
            } label: {
                ZStack {
                    Circle().fill(NestColor.amberGradient).frame(width: 56, height: 56).nestGlowTight()
                    GlyphPath { path, s in
                        path.move(to: CGPoint(x: 0.5 * s, y: 0.2 * s))
                        path.addLine(to: CGPoint(x: 0.5 * s, y: 0.8 * s))
                        path.move(to: CGPoint(x: 0.2 * s, y: 0.5 * s))
                        path.addLine(to: CGPoint(x: 0.8 * s, y: 0.5 * s))
                    }
                    .stroke(NestColor.inkOnAmber, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create evening")
        }
    }

    // MARK: Upcoming

    @ViewBuilder
    private var upcomingContent: some View {
        VStack(alignment: .leading, spacing: NestSpace.xl) {
            if let draft = presenter.draft {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    SectionHead("Draft", subtitle: "Picked up where you left off.")
                    Button {
                        NestHaptics.tap()
                        presenter.showWizard = true
                    } label: {
                        EveningCard(evening: draft,
                                    viewers: presenter.viewers(for: draft),
                                    title: store.title(id: draft.titleId))
                    }
                    .buttonStyle(.plain)
                }
            }

            if presenter.upcoming.isEmpty && presenter.draft == nil {
                NestCard {
                    EmptyStateView(title: "No Evening Planned",
                                   message: store.activeTitles.isEmpty
                                    ? "Add a few titles first, then plan an evening around the time you actually have."
                                    : "Plan one and the app will check it against everyone watching, the window before bedtime and your own rules.",
                                   primaryTitle: store.activeTitles.isEmpty ? "Add Title" : "Create Evening",
                                   primaryAction: {
                                       if store.activeTitles.isEmpty {
                                           router.openLibraryAdd()
                                       } else {
                                           presenter.showWizard = true
                                       }
                                   })
                }
            } else {
                ForEach(presenter.upcoming) { evening in
                    VStack(alignment: .leading, spacing: NestSpace.s) {
                        EveningCard(evening: evening,
                                    viewers: presenter.viewers(for: evening),
                                    title: store.title(id: evening.titleId))
                        HStack(spacing: NestSpace.m) {
                            if evening.state == .awaitingReactions {
                                Button("Record What Happened") { router.openAfterWatch(evening.id) }
                                    .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                            } else {
                                Button(evening.watch.startedAt == nil ? "Start Watch Mode" : "Resume Watch Mode") {
                                    router.openWatch(evening.id)
                                }
                                .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                            }
                            Spacer()
                            if let titleId = evening.titleId {
                                NavigationLink(destination: SuitabilityView(titleId: titleId,
                                                                            preselectedViewers: evening.viewerIds)) {
                                    Text("The Check")
                                        .font(NestFont.smallMedium)
                                        .foregroundColor(NestColor.inkSoft)
                                }
                            }
                            Button("Remove") {
                                NestHaptics.tap()
                                store.deleteEvening(id: evening.id)
                                presenter.show(NestToast(message: "Evening removed"))
                            }
                            .buttonStyle(QuietButtonStyle(tint: NestColor.stop))
                        }
                    }
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: NestSpace.l) {
            NestSearchField(placeholder: "Search", text: $presenter.search)

            VStack(alignment: .leading, spacing: NestSpace.s) {
                SectionLabel("filter by viewer")
                ChipFlow(items: presenter.viewers) { viewer in
                    NestChip(title: viewer.name,
                             selected: presenter.filterViewerId == viewer.id,
                             tint: NestColor.viewerHue(viewer.colourIndex)) {
                        presenter.filterViewerId = presenter.filterViewerId == viewer.id ? nil : viewer.id
                    }
                }
            }

            VStack(alignment: .leading, spacing: NestSpace.s) {
                SectionLabel("filter by outcome")
                ChipFlow(items: EveningOutcome.allCases) { outcome in
                    NestChip(title: outcome.title,
                             selected: presenter.filterOutcome == outcome) {
                        presenter.filterOutcome = presenter.filterOutcome == outcome ? nil : outcome
                    }
                }
            }

            if presenter.filterViewerId != nil || presenter.filterOutcome != nil || !presenter.search.isEmpty {
                Button("Clear Filters") { presenter.clearFilters() }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.stop))
            }

            if presenter.history.isEmpty {
                NestCard {
                    EmptyStateView(title: store.completedEvenings.isEmpty ? "No Evenings Yet" : "Nothing Matches",
                                   message: store.completedEvenings.isEmpty
                                    ? "Once an evening is finished and its reactions are recorded, it lands here — and Insights starts having something honest to say."
                                    : "No completed evening matches those filters.")
                }
            } else {
                ForEach(presenter.historyGroups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        SectionHead(TimeFormat.dayFormatter.string(from: group.day))
                        ForEach(group.evenings) { evening in
                            NavigationLink(destination: EveningRecapView(eveningId: evening.id)) {
                                EveningCard(evening: evening,
                                            viewers: presenter.viewers(for: evening),
                                            title: store.title(id: evening.titleId))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct EveningCard: View {
    let evening: Evening
    let viewers: [Viewer]
    let title: Title?

    var body: some View {
        NestCard(padding: NestSpace.m) {
            HStack(alignment: .top, spacing: NestSpace.m) {
                if let title = title {
                    PosterView(title: title, width: 58)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: NestRadius.chip, style: .continuous)
                            .fill(NestColor.surfaceSunk)
                        NestMark(size: 26, tint: NestColor.border, seat: 1, lineWidth: 2)
                    }
                    .frame(width: 58, height: 87)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(evening.titleSnapshot?.name ?? evening.displayName)
                        .font(NestFont.titleTight)
                        .foregroundColor(NestColor.ink)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: NestSpace.s) {
                        nestTracked(stateLabel.lowercased(), kern: 0.7)
                            .font(NestFont.label)
                            .foregroundColor(stateColour)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(stateColour.opacity(0.14)))
                        if !evening.exceptions.isEmpty {
                            nestTracked("exception", kern: 0.7)
                                .font(NestFont.label)
                                .foregroundColor(NestColor.plum)
                        }
                        Spacer(minLength: 0)
                    }

                    if !viewers.isEmpty {
                        ViewerTokenRow(viewers: viewers, size: 22)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [TimeFormat.shortDayFormatter.string(from: evening.date),
                               evening.startTime.display,
                               evening.occasion.title]
        if evening.plannedRuntimeMinutes > 0 { parts.append("\(evening.plannedRuntimeMinutes) min") }
        if let episode = evening.episodeRef { parts.append(episode.label) }
        return parts.joined(separator: " · ")
    }

    private var stateLabel: String {
        // Until the reactions are in, that is the fact worth showing — not how
        // the film happened to end.
        if evening.state == .awaitingReactions { return evening.state.title }
        return evening.outcome?.title ?? evening.state.title
    }

    private var stateColour: Color {
        if evening.state == .awaitingReactions { return NestColor.stop }
        if let outcome = evening.outcome {
            switch outcome {
            case .finished: return NestColor.go
            case .stoppedEarly: return NestColor.stop
            case .splitAcrossEvenings, .replacedMidEvening: return NestColor.plum
            }
        }
        switch evening.state {
        case .draft: return NestColor.inkFaint
        case .planned: return NestColor.amberSunk
        case .watching: return NestColor.plum
        case .awaitingReactions: return NestColor.stop
        case .completed: return NestColor.go
        }
    }
}

// MARK: - Recap

struct EveningRecapView: View {
    let eveningId: UUID

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @State private var toast: NestToast?

    private var evening: Evening? { store.evening(id: eveningId) }

    var body: some View {
        ZStack {
            NestScreen(bottomInset: NestSpace.huge) {
                if let evening = evening {
                    header(evening)
                    factsCard(evening)
                    if !evening.reactions.isEmpty { reactions(evening) }
                    if !evening.parentNote.isEmpty { parentNote(evening) }
                    if !evening.watch.marks.isEmpty { marks(evening) }
                    if !evening.exceptions.isEmpty { exceptions(evening) }
                    actions(evening)
                } else {
                    ErrorStateView(title: "Evening not found",
                                   message: "It may have been removed.")
                }
            }
            ToastOverlay(toast: toast)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ evening: Evening) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            PageTitle(title: evening.titleSnapshot?.name ?? evening.displayName,
                      subtitle: TimeFormat.dayFormatter.string(from: evening.date))
            HStack(spacing: NestSpace.s) {
                nestTracked((evening.outcome?.title ?? evening.state.title).lowercased(), kern: 0.8)
                    .font(NestFont.label)
                    .foregroundColor(NestColor.amberSunk)
                Spacer()
            }
            ViewerTokenRow(viewers: store.viewers(ids: evening.viewerIds), size: 30)
        }
    }

    private func factsCard(_ evening: Evening) -> some View {
        NestRowGroup {
            recapRow("Occasion", evening.occasion.title)
            RowDivider()
            recapRow("Started", evening.startTime.display)
            RowDivider()
            recapRow("Planned runtime", "\(evening.plannedRuntimeMinutes) min")
            RowDivider()
            recapRow("Actually watched", "\(ScreenTimeEngine.watchedMinutes(evening)) min")
            RowDivider()
            recapRow("Certificate at the time",
                     evening.titleSnapshot?.certificationCode ?? "None recorded")
            if let reason = evening.watch.stopReason {
                RowDivider()
                recapRow("Stopped because", reason.title)
            }
        }
    }

    private func recapRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: NestSpace.m) {
            SectionLabel(label)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(NestFont.body)
                .foregroundColor(NestColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NestSpace.m)
    }

    private func reactions(_ evening: Evening) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("What Happened")
            ForEach(evening.reactions) { reaction in
                if let viewer = store.viewer(id: reaction.viewerId) {
                    NestCard {
                        VStack(alignment: .leading, spacing: NestSpace.s) {
                            HStack(spacing: NestSpace.m) {
                                ViewerToken(viewer: viewer, size: 32)
                                Text(viewer.name)
                                    .font(NestFont.bodyMedium)
                                    .foregroundColor(NestColor.ink)
                                Spacer()
                                if let impression = reaction.impression {
                                    NestChip(title: impression.title, selected: true,
                                             tint: impression.weight >= 4 ? NestColor.go : NestColor.amber)
                                }
                            }
                            let flags = summaryFlags(reaction)
                            if !flags.isEmpty {
                                Text(flags.joined(separator: " · "))
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkSoft)
                            }
                            if !reaction.bestMoment.isEmpty {
                                Text("Best moment: \(reaction.bestMoment)")
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !reaction.privateNote.isEmpty {
                                Text(reaction.privateNote)
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func summaryFlags(_ reaction: Reaction) -> [String] {
        var flags: [String] = []
        if reaction.watchedToEnd { flags.append("watched to the end") }
        if reaction.gotScared { flags.append("got scared") }
        if reaction.askedQuestions { flags.append("asked questions") }
        if reaction.fellAsleep { flags.append("fell asleep") }
        if reaction.wantsAgain { flags.append("wants it again") }
        return flags
    }

    private func parentNote(_ evening: Evening) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Parent Note")
            NestCard {
                Text(evening.parentNote)
                    .font(NestFont.body)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func marks(_ evening: Evening) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Marked Moments")
            NestCard {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    ForEach(evening.watch.marks) { mark in
                        HStack(spacing: NestSpace.m) {
                            Text(mark.timecode)
                                .font(NestFont.figureSmall)
                                .foregroundColor(NestColor.ink)
                                .frame(width: 56, alignment: .leading)
                            NestChip(title: mark.kind.title, selected: mark.kind.isCautionary,
                                     tint: mark.kind.isCautionary ? NestColor.stop : NestColor.go)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func exceptions(_ evening: Evening) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Exceptions")
            ForEach(evening.exceptions) { exception in
                NestCard(tint: NestColor.plumWash, stroke: NestColor.plum.opacity(0.35)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rule broken on purpose: \(exception.reason)")
                            .font(NestFont.body)
                            .foregroundColor(NestColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(exception.ruleTitle)
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                    }
                }
            }
        }
    }

    private func actions(_ evening: Evening) -> some View {
        VStack(spacing: NestSpace.m) {
            MinuteTicks(count: 40, height: 5, emphasisEvery: 5, colour: NestColor.hairline)

            if evening.state == .completed {
                Text("Finished evenings are kept as they were. Watch Again creates a new evening with its own date.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Watch Again") {
                    var fresh = Evening()
                    fresh.name = evening.name
                    fresh.date = Date()
                    fresh.startTime = evening.startTime
                    fresh.occasion = evening.occasion
                    fresh.viewerIds = evening.viewerIds
                    fresh.window = store.profile.defaultWindow(on: Date())
                    fresh.titleId = evening.titleId
                    fresh.titleSnapshot = evening.titleSnapshot
                    fresh.episodeRef = evening.episodeRef
                    fresh.state = .planned
                    fresh.planningStartedAt = Date()
                    fresh.continuedFromEveningId = evening.id
                    store.upsertEvening(fresh)
                    NotificationService.shared.reschedule(for: store.document)
                    show(NestToast(message: "New evening created"))
                }
            } else if evening.state == .awaitingReactions {
                PrimaryButton(title: "Record What Happened") {
                    router.openAfterWatch(evening.id)
                }
            }

            if let titleId = evening.titleId {
                NavigationLink(destination: TitleDetailView(titleId: titleId)) {
                    Text("Open the Title")
                        .font(NestFont.heading)
                        .foregroundColor(NestColor.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                                .fill(NestColor.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                                .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, NestSpace.s)
    }

    private func show(_ value: NestToast) {
        toast = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toast == value { toast = nil }
        }
    }
}
