//  OnlineSearchModule.swift
//  Screen Nest — "Search Online".
//
//  Nothing is requested until the parent presses Search. Results are cached and
//  work again offline. Every failure has its own designed state and its own
//  honest sentence, and every one of them ends the same way: add it by hand.

import SwiftUI

enum OnlineSearchState {
    case idle
    case searching
    case results([TMDBSearchResult])
    case empty
    case failed(String)
}

final class OnlineSearchPresenter: ObservableObject {
    @Published var term: String = ""
    @Published private(set) var state: OnlineSearchState = .idle
    @Published var loadingDetailFor: Int?

    private let service = TMDBService.shared
    private var task: Task<Void, Never>?

    var hasKey: Bool { service.hasKey }
    var isAllowed: Bool { service.isAllowed }
    var isOnline: Bool { NetworkMonitor.shared.isOnline }

    deinit { task?.cancel() }

    func search() {
        task?.cancel()
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }

        state = .searching
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                let results = try await self.service.search(query)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.state = results.isEmpty ? .empty : .results(results)
                }
            } catch {
                if Task.isCancelled { return }
                let message = (error as? TMDBError)?.errorDescription ?? TMDBError.failed.errorDescription ?? ""
                await MainActor.run {
                    if case TMDBError.notFound = error {
                        self.state = .empty
                    } else {
                        self.state = .failed(message)
                    }
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        state = .idle
    }

    /// Pulls the detail and the poster, then hands a prefilled form back.
    func choose(_ result: TMDBSearchResult, country: RatingCountry, completion: @escaping (TitlePrefill) -> Void) {
        guard loadingDetailFor == nil else { return }
        loadingDetailFor = result.id
        Task { [weak self] in
            guard let self = self else { return }
            let detail = try? await self.service.detail(for: result, country: country)
            let image = await self.service.posterImage(path: detail?.posterPath ?? result.posterPath)
            let prefill = TitlePrefill(
                name: result.name,
                originalName: result.originalName,
                type: result.isSeries ? .series : .film,
                runtimeMinutes: detail?.runtimeMinutes,
                genres: detail?.genres ?? [],
                releaseYear: detail?.year ?? result.year,
                certificationCode: detail?.certification,
                certificationMissing: detail?.certificationMissing ?? true,
                shortDescription: detail?.overview ?? result.overview,
                aspects: detail?.aspects ?? [],
                poster: image,
                tmdbId: result.id,
                seasons: detail?.seasons ?? []
            )
            await MainActor.run {
                self.loadingDetailFor = nil
                completion(prefill)
            }
        }
    }
}

struct OnlineSearchView: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter = OnlineSearchPresenter()
    @ObservedObject private var monitor = NetworkMonitor.shared

    let onChosen: (TitlePrefill) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetScaffold(title: "Search Online",
                      subtitle: "Fills in running time, genres, the certificate for your country and a poster.",
                      closeTitle: "Cancel",
                      onClose: onCancel) {

            HStack(spacing: NestSpace.s) {
                NestSearchField(placeholder: "Film or series title", text: $presenter.term) {
                    presenter.search()
                }
                Button("Search") { presenter.search() }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
            }

            if !monitor.isOnline {
                offlineNotice
            }

            content

            attribution
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        if !presenter.hasKey {
            NestCard {
                EmptyStateView(
                    title: "Online Search Is Unavailable",
                    message: "This build has no search service configured. Everything else — adding by hand, planning, watching and recording what happened — works exactly the same.",
                    primaryTitle: "Add by Hand",
                    primaryAction: { onChosen(prefillFromTerm) }
                )
            }
        } else if !presenter.isAllowed {
            NestCard {
                EmptyStateView(
                    title: "Online Search Is Switched Off",
                    message: "Online search is off in Settings → External Data, so the app is not touching the network at all. Titles can still be added by hand.",
                    primaryTitle: "Add by Hand",
                    primaryAction: { onChosen(prefillFromTerm) }
                )
            }
        } else {
            switch presenter.state {
            case .idle:
                NestCard {
                    EmptyStateView(title: "Type a Title",
                                   message: "Nothing is requested until you press Search. No catalogue is downloaded in the background.")
                }

            case .searching:
                LoadingStateView(message: "Looking it up…")

            case .empty:
                NestCard {
                    EmptyStateView(title: "Nothing Found",
                                   message: "Nothing found. Check the title or add it by hand.",
                                   primaryTitle: "Add by Hand",
                                   primaryAction: { onChosen(prefillFromTerm) })
                }

            case .failed(let message):
                ErrorStateView(title: "Search Did Not Complete",
                               message: message,
                               retryTitle: "Try Again") {
                    presenter.search()
                }

            case .results(let results):
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    SectionLabel("\(results.count) result\(results.count == 1 ? "" : "s")")
                    ForEach(results) { result in
                        Button {
                            NestHaptics.tap()
                            presenter.choose(result, country: store.profile.ratingCountry, completion: onChosen)
                        } label: {
                            SearchResultRow(result: result,
                                            busy: presenter.loadingDetailFor == result.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(presenter.loadingDetailFor != nil)
                    }

                    Button("None of these — add by hand") { onChosen(prefillFromTerm) }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, NestSpace.xs)
                }
            }
        }
    }

    private var offlineNotice: some View {
        NestCard(tint: NestColor.amberWash, stroke: NestColor.amber.opacity(0.4)) {
            VStack(alignment: .leading, spacing: NestSpace.s) {
                SectionLabel("offline", colour: NestColor.amberSunk)
                Text("Offline. You can add titles by hand, plan the evening and watch — only online search is unavailable.")
                    .font(NestFont.body)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Anything found before is still available from the cache.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
            }
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            MinuteTicks(count: 30, height: 4, emphasisEvery: 5, colour: NestColor.hairline)
            HStack(spacing: NestSpace.s) {
                TMDBMark()
                Text(TMDBService.attribution)
                    .font(NestFont.micro)
                    .foregroundColor(NestColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, NestSpace.m)
    }

    private var prefillFromTerm: TitlePrefill {
        TitlePrefill(name: presenter.term.trimmingCharacters(in: .whitespaces),
                     originalName: "",
                     type: .film,
                     runtimeMinutes: nil,
                     genres: [],
                     releaseYear: nil,
                     certificationCode: nil,
                     certificationMissing: false,
                     shortDescription: "",
                     aspects: [],
                     poster: nil,
                     tmdbId: nil,
                     seasons: [])
    }

}

struct SearchResultRow: View {
    let result: TMDBSearchResult
    let busy: Bool

    var body: some View {
        NestCard(padding: NestSpace.m) {
            HStack(alignment: .top, spacing: NestSpace.m) {
                RemotePoster(path: result.posterPath)
                    .frame(width: 56, height: 84)
                    .clipShape(PosterShape())
                    .overlay(PosterShape().stroke(NestColor.hairline, lineWidth: NestStroke.hair))

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(NestFont.titleTight)
                        .foregroundColor(NestColor.ink)
                        .multilineTextAlignment(.leading)
                    Text([result.typeLabel, result.year.map(String.init)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                    if !result.overview.isEmpty {
                        Text(result.overview)
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkFaint)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                if busy {
                    BusyTicks().padding(.top, 4)
                } else {
                    Chevron().padding(.top, 4)
                }
            }
        }
    }
}

/// Remote poster with the app's own placeholder rather than a grey box.
struct RemotePoster: View {
    let path: String?

    var body: some View {
        Group {
            if let path = path, let url = URL(string: "https://image.tmdb.org/t/p/w185" + path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            NestColor.surfaceSunk
            NestMark(size: 28, tint: NestColor.border, seat: 1, lineWidth: 2)
        }
    }
}

/// The TMDB word-mark, drawn so it needs no bundled asset.
struct TMDBMark: View {
    var body: some View {
        Text("TMDB")
            .font(NestFont.markWord)
            .foregroundColor(NestColor.surface)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: [Color(nestHex: 0x90CEA1), Color(nestHex: 0x01B4E4)],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .accessibilityLabel("The Movie Database")
    }
}
