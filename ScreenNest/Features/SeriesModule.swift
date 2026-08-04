//  SeriesModule.swift
//  Screen Nest — series progress.
//
//  For a series the evening window is measured against the episode, and the
//  number of episodes in one sitting is bounded by the house rule if one exists.

import SwiftUI

final class SeriesPresenter: ObservableObject {
    @Published var toast: NestToast?
    @Published var confirmingFinish = false

    let titleId: UUID
    private let store: DataStore

    init(titleId: UUID, store: DataStore) {
        self.titleId = titleId
        self.store = store
    }

    var title: Title? { store.title(id: titleId) }
    var position: SeriesPosition { title?.seriesPosition ?? SeriesPosition() }

    /// How many episodes fit in tonight's window, capped by the one-per-evening rule.
    func episodesTonight(window: EveningWindow) -> Int {
        guard let runtime = title?.nextEpisode?.episode.runtimeMinutes, runtime > 0 else { return 0 }
        let byTime = window.filmMinutes / runtime
        let hasCap = store.activeRules.contains { $0.isActive && $0.type == .oneFilmPerEvening }
        return hasCap ? min(1, byTime) : byTime
    }

    func markWatched(season: Int, episode: Int) {
        store.updateSeriesPosition(titleId: titleId, season: season, episode: episode)
        NestHaptics.success()
        show(NestToast(message: "Episode marked watched"))
    }

    func skip(season: Int, episode: Int) {
        store.updateSeriesPosition(titleId: titleId, season: season, episode: episode)
        NestHaptics.tap()
        show(NestToast(message: "Episode skipped"))
    }

    func rewind(season: Int, episode: Int) {
        store.updateSeriesPosition(titleId: titleId, season: season, episode: max(0, episode - 1))
        NestHaptics.tap()
    }

    func finishSeries() {
        guard let title = title,
              let lastSeason = title.seasons.map(\.number).max(),
              let lastEpisode = title.seasons.first(where: { $0.number == lastSeason })?
                .episodes.map(\.number).max()
        else { return }
        store.updateSeriesPosition(titleId: titleId, season: lastSeason, episode: lastEpisode)
        NestHaptics.success()
        show(NestToast(message: "Series finished"))
    }

    func restart() {
        store.updateSeriesPosition(titleId: titleId, season: 1, episode: 0)
        NestHaptics.tap()
        show(NestToast(message: "Back to the beginning"))
    }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct SeriesDetailView: View {
    let titleId: UUID

    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter: SeriesPresenter
    @State private var wizardOpen = false

    init(titleId: UUID) {
        self.titleId = titleId
        _presenter = StateObject(wrappedValue: SeriesPresenter(titleId: titleId, store: .shared))
    }

    private var window: EveningWindow {
        SuitabilityService(store: store).window(for: store.viewers)
    }

    var body: some View {
        ZStack {
            NestScreen(bottomInset: NestSpace.huge) {
                if let title = presenter.title {
                    PageTitle(title: title.name, subtitle: "Series progress")

                    NestPanel(label: "continue watching", glow: true) {
                        VStack(alignment: .leading, spacing: NestSpace.m) {
                            SeriesProgressPanel(title: title)

                            let fit = presenter.episodesTonight(window: window)
                            Text(fit == 0
                                 ? "Tonight's window of \(window.filmMinutes) minutes does not hold a full episode."
                                 : "Tonight's window of \(window.filmMinutes) minutes holds \(fit) episode\(fit == 1 ? "" : "s").")
                                .font(NestFont.small)
                                .foregroundColor(fit == 0 ? NestColor.stop : NestColor.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)

                            if store.activeRules.contains(where: { $0.type == .oneFilmPerEvening && $0.isActive }) {
                                Text("House rule: one per evening — capped at a single episode.")
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.amberSunk)
                            }

                            if let next = title.nextEpisode {
                                PrimaryButton(title: "Plan S\(next.season) · E\(next.episode.number)") {
                                    wizardOpen = true
                                }
                            }
                        }
                    }

                    if title.seasons.isEmpty {
                        NestCard {
                            EmptyStateView(title: "No Episodes Recorded",
                                           message: "Add seasons and episodes by editing the title, or bring them in with an online search.")
                        }
                    } else {
                        seasonsList(title)
                    }

                    controls(title)
                } else {
                    ErrorStateView(title: "Series not found", message: "It may have been removed from the library.")
                }
            }
            ToastOverlay(toast: presenter.toast)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $wizardOpen) {
            EveningWizardView(prefilledTitleId: titleId) {
                wizardOpen = false
                presenter.show(NestToast(message: "Evening created"))
            } onCancel: {
                wizardOpen = false
            }
        }
    }

    private func seasonsList(_ title: Title) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.l) {
            ForEach(title.seasons.sorted { $0.number < $1.number }) { season in
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    SectionHead(season.name.isEmpty ? "Season \(season.number)" : season.name,
                                subtitle: "\(season.episodes.count) episode\(season.episodes.count == 1 ? "" : "s")")
                    NestCard(padding: NestSpace.m) {
                        VStack(spacing: 0) {
                            ForEach(Array(season.episodes.sorted { $0.number < $1.number }.enumerated()),
                                    id: \.element.id) { index, episode in
                                episodeRow(season: season, episode: episode, title: title)
                                if index < season.episodes.count - 1 { RowDivider() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func episodeRow(season: SeriesSeason, episode: Episode, title: Title) -> some View {
        let position = presenter.position
        let watched = season.number < position.seasonNumber
            || (season.number == position.seasonNumber && episode.number <= position.episodeNumber)
        let isNext = title.nextEpisode.map { $0.season == season.number && $0.episode.number == episode.number } ?? false

        return HStack(spacing: NestSpace.m) {
            ZStack {
                Circle()
                    .stroke(watched ? NestColor.go : (isNext ? NestColor.amber : NestColor.border), lineWidth: NestStroke.mark)
                    .frame(width: 20, height: 20)
                if watched {
                    GlyphPath { path, s in
                        path.move(to: CGPoint(x: 0.24 * s, y: 0.52 * s))
                        path.addLine(to: CGPoint(x: 0.44 * s, y: 0.72 * s))
                        path.addLine(to: CGPoint(x: 0.78 * s, y: 0.30 * s))
                    }
                    .stroke(NestColor.go, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("E\(episode.number) · \(episode.name.isEmpty ? "Episode \(episode.number)" : episode.name)")
                    .font(NestFont.bodyMedium)
                    .foregroundColor(watched ? NestColor.inkFaint : NestColor.ink)
                    .multilineTextAlignment(.leading)
                Text("\(episode.runtimeMinutes) min")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
            }

            Spacer()

            if watched {
                Button("Undo") {
                    presenter.rewind(season: season.number, episode: episode.number)
                }
                .buttonStyle(QuietButtonStyle(tint: NestColor.inkFaint))
            } else {
                HStack(spacing: NestSpace.m) {
                    Button("Skip") {
                        presenter.skip(season: season.number, episode: episode.number)
                    }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.inkFaint))
                    Button("Watched") {
                        presenter.markWatched(season: season.number, episode: episode.number)
                    }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.go))
                }
            }
        }
        .padding(.vertical, NestSpace.s)
    }

    private func controls(_ title: Title) -> some View {
        VStack(spacing: NestSpace.m) {
            MinuteTicks(count: 40, height: 5, emphasisEvery: 5, colour: NestColor.hairline)
            if title.episodesLeft > 0 && !title.seasons.isEmpty {
                Button("Finish Series") {
                    NestHaptics.tap()
                    presenter.confirmingFinish = true
                }
                .buttonStyle(SecondaryButtonStyle())
                .alert("Mark every episode watched?", isPresented: $presenter.confirmingFinish) {
                    Button("Cancel", role: .cancel) {}
                    Button("Finish Series") { presenter.finishSeries() }
                }
            }
            Button("Start Again from Episode One") {
                presenter.restart()
            }
            .buttonStyle(QuietButtonStyle(tint: NestColor.inkSoft))
        }
        .padding(.top, NestSpace.s)
    }
}

// MARK: - Series in progress list

struct SeriesListView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter

    private var series: [Title] {
        store.activeTitles.filter { $0.type.isEpisodic }
    }

    var body: some View {
        NestScreen(bottomInset: NestSpace.huge) {
            PageTitle(title: "Series",
                      subtitle: "Where each one is up to, and whether the next episode fits tonight.")

            if series.isEmpty {
                NestCard {
                    EmptyStateView(title: "No Series Yet",
                                   message: "Add a title with the type Series and the app keeps the position for you.",
                                   primaryTitle: "Add Title",
                                   primaryAction: { router.openLibraryAdd() })
                }
            } else {
                ForEach(series) { title in
                    NavigationLink(destination: SeriesDetailView(titleId: title.id)) {
                        NestCard(padding: NestSpace.m) {
                            HStack(alignment: .top, spacing: NestSpace.m) {
                                PosterView(title: title, width: 58)
                                VStack(alignment: .leading, spacing: NestSpace.s) {
                                    Text(title.name)
                                        .font(NestFont.titleTight)
                                        .foregroundColor(NestColor.ink)
                                        .multilineTextAlignment(.leading)
                                    SeriesProgressPanel(title: title)
                                }
                                Chevron().padding(.top, 4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
