//  HomeModule.swift
//  Screen Nest — "Tonight".
//
//  The page changes shape with the data: an empty house gets a real invitation,
//  a full one gets the window, what fits, who is watching, what is left of the
//  week, and the single next step worth taking.

import SwiftUI

// MARK: - Entities

struct NextStep: Identifiable {
    let id = UUID()
    let label: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: NextStepAction
}

enum NextStepAction {
    case recordReactions(UUID)
    case resumeWatch(UUID)
    case fillSensitivities(UUID)
    case addTitle
    case addViewer
    case planEvening
    case shorterTitles
}

// MARK: - Interactor

protocol HomeInteracting {
    func snapshot(date: Date) -> HomeSnapshot
}

struct HomeSnapshot {
    var isLoaded: Bool
    var loadError: String?
    var viewers: [Viewer]
    var window: EveningWindow
    var fits: [(title: Title, result: SuitabilityResult)]
    var screenTime: [ScreenTimeWeek]
    var unfinished: Evening?
    var awaitingReactions: [Evening]
    var recentlyWatched: [Evening]
    var nextStep: NextStep?
    var libraryCount: Int
}

struct HomeInteractor: HomeInteracting {
    let store: DataStore

    func snapshot(date: Date) -> HomeSnapshot {
        let service = SuitabilityService(store: store)
        let viewers = store.viewers
        let window = service.window(for: viewers, on: date)
        let ranked = viewers.isEmpty ? [] : service.rank(viewers: viewers, date: date, window: window)
        let fits = ranked.filter { $0.result.status.isOffer }

        let unfinished = store.unfinishedEvening
        let awaiting = store.evenings
            .filter { $0.state == .awaitingReactions }
            .sorted { $0.date > $1.date }
        let recent = store.completedEvenings.prefix(4).map { $0 }

        return HomeSnapshot(
            isLoaded: store.isLoaded,
            loadError: store.loadError,
            viewers: viewers,
            window: window,
            fits: Array(fits.prefix(3)),
            screenTime: ScreenTimeEngine.allWeeks(in: store.document, date: date),
            unfinished: unfinished,
            awaitingReactions: awaiting,
            recentlyWatched: Array(recent),
            nextStep: makeNextStep(viewers: viewers,
                                   window: window,
                                   ranked: ranked,
                                   unfinished: unfinished,
                                   awaiting: awaiting),
            libraryCount: store.activeTitles.count
        )
    }

    /// Exactly one next step, chosen by what is most in the way.
    private func makeNextStep(viewers: [Viewer],
                              window: EveningWindow,
                              ranked: [(title: Title, result: SuitabilityResult)],
                              unfinished: Evening?,
                              awaiting: [Evening]) -> NextStep? {

        if let evening = unfinished {
            let at = TimeFormat.clock(seconds: evening.watch.elapsed())
            return NextStep(label: "next step",
                            title: "Unfinished Evening",
                            detail: "\(evening.titleSnapshot?.name ?? evening.displayName) is paused at \(at).",
                            actionTitle: "Resume From \(at)",
                            action: .resumeWatch(evening.id))
        }

        if let evening = awaiting.first {
            return NextStep(label: "next step",
                            title: "Record What Happened",
                            detail: "\(evening.titleSnapshot?.name ?? evening.displayName) was watched but nobody wrote down how it went.",
                            actionTitle: "Record What Happened",
                            action: .recordReactions(evening.id))
        }

        if viewers.isEmpty {
            return NextStep(label: "next step",
                            title: "Add Your First Viewer",
                            detail: "The check has to be about someone in particular.",
                            actionTitle: "Add Viewer",
                            action: .addViewer)
        }

        if store.activeTitles.isEmpty {
            return NextStep(label: "next step",
                            title: "Fill the Library",
                            detail: "Add a few titles by hand or by search, and the app can start working out what fits.",
                            actionTitle: "Add Title",
                            action: .addTitle)
        }

        if let child = viewers.first(where: { !$0.role.isGrownUp && $0.activeSensitivities.isEmpty }) {
            return NextStep(label: "next step",
                            title: "Tell Me What Scares \(child.name)",
                            detail: "Without this, the check is only about age — which is the part that already exists everywhere else.",
                            actionTitle: "Edit Sensitivities",
                            action: .fillSensitivities(child.id))
        }

        let shortest = store.activeTitles.map(\.runtimeMinutes).filter { $0 > 0 }.min()
        if let shortest = shortest, window.filmMinutes > 0, window.filmMinutes < shortest {
            return NextStep(label: "next step",
                            title: "Only \(window.filmMinutes) Minutes Tonight",
                            detail: "The shortest thing in your library is \(shortest) minutes. Split something over two evenings, or plan for tomorrow.",
                            actionTitle: "Show Everything",
                            action: .shorterTitles)
        }

        if ranked.contains(where: { $0.result.status.isOffer }) {
            return NextStep(label: "next step",
                            title: "Plan Tonight",
                            detail: "Something in the library fits the window you have left.",
                            actionTitle: "Create Evening",
                            action: .planEvening)
        }

        return nil
    }
}

// MARK: - Presenter

final class HomePresenter: ObservableObject {
    @Published private(set) var snapshot: HomeSnapshot
    @Published var showPick = false
    @Published var showScreenTime = false
    @Published var editingViewerId: UUID?

    private let interactor: HomeInteracting

    init(interactor: HomeInteracting) {
        self.interactor = interactor
        snapshot = interactor.snapshot(date: Date())
    }

    func refresh() {
        snapshot = interactor.snapshot(date: Date())
    }

    var isEmptyHouse: Bool {
        snapshot.libraryCount == 0
    }

    var windowCaption: String {
        snapshot.window.sentence
    }
}

// MARK: - View

struct HomeView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter = HomePresenter(interactor: HomeInteractor(store: .shared))

    var body: some View {
        NavigationView {
            NestScreen {
                header

                if !presenter.snapshot.isLoaded {
                    LoadingStateView()
                } else if let error = presenter.snapshot.loadError {
                    ErrorStateView(title: "The saved file could not be read",
                                   message: error,
                                   retryTitle: "Reload") { store.load(); presenter.refresh() }
                } else if presenter.isEmptyHouse {
                    emptyHouse
                } else {
                    populated
                }
            }
            .navigationBarHidden(true)
            .background(
                NavigationLink(destination: PickTonightView(), isActive: $presenter.showPick) { EmptyView() }
                    .hidden()
            )
            .background(
                NavigationLink(destination: ScreenTimeView(), isActive: $presenter.showScreenTime) { EmptyView() }
                    .hidden()
            )
        }
        .navigationViewStyle(.stack)
        .onAppear { presenter.refresh() }
        .onReceive(store.$document.dropFirst()) { _ in presenter.refresh() }
        .sheet(item: Binding(
            get: { presenter.editingViewerId.map(IdentifiedUUID.init) },
            set: { presenter.editingViewerId = $0?.id }
        )) { wrapper in
            if let viewer = store.viewer(id: wrapper.id) {
                ViewerFormView(viewer: viewer,
                               existingCount: store.viewers.count,
                               allowDelete: false,
                               onSave: { updated in
                    store.upsertViewer(updated)
                    presenter.editingViewerId = nil
                }, onDelete: { _ in
                    presenter.editingViewerId = nil
                }, onCancel: {
                    presenter.editingViewerId = nil
                })
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: NestSpace.xs) {
                SectionLabel(greeting)
                Text("Tonight")
                    .font(NestFont.display)
                    .foregroundColor(NestColor.ink)
            }
            Spacer()
            Button {
                NestHaptics.tap()
                router.showSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(NestColor.amberGradient)
                        .frame(width: 48, height: 48)
                        .nestGlowTight()
                    ReasonSymbolGlyph(symbol: .rule, tint: NestColor.inkOnAmber, size: 20)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var greeting: String {
        let name = store.profile.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? TimeFormat.dayFormatter.string(from: Date()) : "\(name) · \(TimeFormat.weekdayFormatter.string(from: Date()))"
    }

    // MARK: Empty

    private var emptyHouse: some View {
        NestCard(glow: true) {
            EmptyStateView(
                title: "Nothing to Watch Yet",
                message: "Add a few films and the app will work out which ones fit tonight, and which ones fit this child.",
                primaryTitle: "Add Title",
                primaryAction: { router.openLibraryAdd() },
                secondaryTitle: "Add Viewer",
                secondaryAction: { router.openViewerAdd() }
            )
        }
    }

    // MARK: Populated

    private var populated: some View {
        VStack(alignment: .leading, spacing: NestSpace.xl) {

            NestPanel(label: "tonight’s window", glow: true) {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    EveningArch()
                        .frame(height: 34)

                    HStack(alignment: .firstTextBaseline, spacing: NestSpace.s) {
                        CountUpNumber(value: presenter.snapshot.window.filmMinutes)
                            .font(NestFont.figureHuge)
                            .foregroundColor(presenter.snapshot.window.filmMinutes > 0 ? NestColor.ink : NestColor.stop)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("minutes")
                                .font(NestFont.body)
                                .foregroundColor(NestColor.inkSoft)
                            Text("for the film itself")
                                .font(NestFont.small)
                                .foregroundColor(NestColor.inkFaint)
                        }
                    }

                    // Solid: the part of the time to bedtime that is genuinely
                    // usable. The remainder is settling, pauses and buffer.
                    WindowBar(fraction: Double(presenter.snapshot.window.filmMinutes)
                                / Double(max(1, presenter.snapshot.window.minutesToBedtime)),
                              filmFraction: nil,
                              height: 14,
                              overflow: presenter.snapshot.window.filmMinutes == 0)

                    Text(presenter.windowCaption)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let step = presenter.snapshot.nextStep {
                nextStepCard(step)
            }

            if let evening = presenter.snapshot.unfinished {
                unfinishedCard(evening)
            }

            fitsTonight

            watchingTonight

            screenTimeLeft

            if !presenter.snapshot.awaitingReactions.isEmpty {
                waitingForReactions
            }

            if !presenter.snapshot.recentlyWatched.isEmpty {
                recentlyWatched
            }
        }
    }

    private func nextStepCard(_ step: NextStep) -> some View {
        NestAmberCard {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                SectionLabel(step.label, colour: NestColor.inkOnAmber.opacity(0.65))
                nestTracked(step.title.uppercased(), kern: -0.3)
                    .font(.system(size: 22, weight: .heavy).italic())
                    .foregroundColor(NestColor.inkOnAmber)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(NestFont.body)
                    .foregroundColor(NestColor.inkOnAmber.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
                Button(step.actionTitle) {
                    NestHaptics.tap()
                    perform(step.action)
                }
                .buttonStyle(SecondaryButtonStyle(tint: NestColor.inkOnAmber))
                .padding(.top, NestSpace.xs)
            }
        }
    }

    private func unfinishedCard(_ evening: Evening) -> some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                SectionLabel("unfinished evening")
                Text(evening.titleSnapshot?.name ?? evening.displayName)
                    .font(NestFont.titleTight)
                    .foregroundColor(NestColor.ink)
                WindowBar(fraction: progressFraction(evening), height: 10, showTicks: false)
                HStack {
                    Text("Stopped at \(TimeFormat.clock(seconds: evening.watch.elapsed()))")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                    Spacer()
                    Button("Resume Watch Mode") { router.openWatch(evening.id) }
                        .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                }
            }
        }
    }

    private func progressFraction(_ evening: Evening) -> Double {
        let runtime = max(1, evening.plannedRuntimeMinutes * 60)
        return min(1, Double(evening.watch.elapsed()) / Double(runtime))
    }

    private var fitsTonight: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title: "Fits Tonight",
                        subtitle: presenter.snapshot.fits.isEmpty
                            ? nil
                            : "Checked against everyone who is watching, not against an average child.") {
                Button("Show Everything") { presenter.showPick = true }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
            }

            if presenter.snapshot.viewers.isEmpty {
                NestCard {
                    EmptyStateView(title: "Nobody to Check Against",
                                   message: "Add a viewer and the app can tell you what fits them.",
                                   primaryTitle: "Add Viewer",
                                   primaryAction: { router.openViewerAdd() })
                }
            } else if presenter.snapshot.fits.isEmpty {
                NestCard {
                    EmptyStateView(title: "Nothing Fits Tonight",
                                   message: "Everything in the library is blocked by the window, a rule, an age or a sensitivity. The reasons are on the next screen — you can still choose anything you like.",
                                   primaryTitle: "Show Everything",
                                   primaryAction: { presenter.showPick = true })
                }
            } else {
                ForEach(presenter.snapshot.fits, id: \.title.id) { entry in
                    NavigationLink(destination: SuitabilityView(titleId: entry.title.id)) {
                        TitleOfferCard(title: entry.title, result: entry.result)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var watchingTonight: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title: "Watching Tonight") {
                Button("Edit") { router.tab = .viewers }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
            }
            NestCard {
                if presenter.snapshot.viewers.isEmpty {
                    Text("No viewers yet.")
                        .font(NestFont.body)
                        .foregroundColor(NestColor.inkFaint)
                } else {
                    HStack(spacing: NestSpace.l) {
                        ForEach(presenter.snapshot.viewers) { viewer in
                            Button {
                                NestHaptics.tap()
                                presenter.editingViewerId = viewer.id
                            } label: {
                                ViewerToken(viewer: viewer, size: 42, showName: true)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var screenTimeLeft: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title: "Screen Time Left") {
                Button("This Week") { presenter.showScreenTime = true }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
            }
            NestCard {
                if presenter.snapshot.screenTime.isEmpty {
                    Text("No weekly limits are being kept. You can set one per child in Viewers.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: NestSpace.l) {
                        ForEach(presenter.snapshot.screenTime) { week in
                            ScreenTimeStrip(week: week)
                        }
                    }
                }
            }
        }
    }

    private var waitingForReactions: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Waiting for Reactions",
                        subtitle: "Details fade by tomorrow morning.")
            ForEach(presenter.snapshot.awaitingReactions) { evening in
                NestCard {
                    HStack(spacing: NestSpace.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(evening.titleSnapshot?.name ?? evening.displayName)
                                .font(NestFont.bodyMedium)
                                .foregroundColor(NestColor.ink)
                            Text(TimeFormat.shortDayFormatter.string(from: evening.date))
                                .font(NestFont.small)
                                .foregroundColor(NestColor.inkFaint)
                        }
                        Spacer()
                        Button("Record") { router.openAfterWatch(evening.id) }
                            .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                    }
                }
            }
        }
    }

    private var recentlyWatched: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title: "Recently Watched") {
                Button("History") { router.tab = .evenings }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: NestSpace.m) {
                    ForEach(presenter.snapshot.recentlyWatched) { evening in
                        NavigationLink(destination: EveningRecapView(eveningId: evening.id)) {
                            VStack(alignment: .leading, spacing: NestSpace.s) {
                                if let title = store.title(id: evening.titleId) {
                                    PosterView(title: title, width: 86)
                                } else {
                                    RoundedRectangle(cornerRadius: NestRadius.posterTop, style: .continuous)
                                        .fill(NestColor.surfaceSunk)
                                        .frame(width: 86, height: 119)
                                }
                                Text(evening.titleSnapshot?.name ?? evening.displayName)
                                    .font(NestFont.smallMedium)
                                    .foregroundColor(NestColor.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(evening.outcome?.title ?? evening.state.title)
                                    .font(NestFont.micro)
                                    .foregroundColor(NestColor.inkFaint)
                            }
                            .frame(width: 86)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Actions

    private func perform(_ action: NextStepAction) {
        switch action {
        case .recordReactions(let id): router.openAfterWatch(id)
        case .resumeWatch(let id): router.openWatch(id)
        case .fillSensitivities(let id): presenter.editingViewerId = id
        case .addTitle: router.openLibraryAdd()
        case .addViewer: router.openViewerAdd()
        case .planEvening: router.openWizard()
        case .shorterTitles: presenter.showPick = true
        }
    }
}

// MARK: - Shared cards

struct TitleOfferCard: View {
    let title: Title
    let result: SuitabilityResult
    @AppStorage(NestDefaults.showPosters) private var showPosters: Bool = true

    var body: some View {
        TicketCard(padding: NestSpace.m) {
            HStack(alignment: .top, spacing: NestSpace.m) {
                PosterView(title: title, width: 72, showPoster: showPosters)

                VStack(alignment: .leading, spacing: NestSpace.s) {
                    HStack(alignment: .top) {
                        Text(title.name)
                            .font(NestFont.titleTight)
                            .foregroundColor(NestColor.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: NestSpace.s)
                        StatusPill(status: result.status, compact: true)
                    }

                    Text(result.headline)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    if !title.contentAspects.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(title.contentAspects.prefix(6), id: \.self) { aspect in
                                AspectGlyph(aspect: aspect, size: 18, tint: NestColor.inkSoft, lineWidth: 2)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ScreenTimeStrip: View {
    let week: ScreenTimeWeek

    var body: some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(week.viewerName)
                    .font(NestFont.bodyMedium)
                    .foregroundColor(NestColor.ink)
                Spacer()
                if let remaining = week.remainingMinutes {
                    Text("\(remaining) min left")
                        .font(NestFont.figureMicro)
                        .foregroundColor(remaining < 0 ? NestColor.stop : NestColor.inkSoft)
                } else {
                    Text("no limit kept")
                        .font(NestFont.micro)
                        .foregroundColor(NestColor.inkFaint)
                }
            }
            WindowBar(fraction: week.fraction, height: 9, overflow: week.isOver, showTicks: false)
            Text("\(week.usedMinutes) of \(week.allowanceMinutes.map(String.init) ?? "—") minutes used this week")
                .font(NestFont.micro)
                .foregroundColor(NestColor.inkFaint)
        }
    }
}
