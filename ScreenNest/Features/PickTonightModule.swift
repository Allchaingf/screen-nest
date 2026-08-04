//  PickTonightModule.swift
//  Screen Nest — "Pick for Tonight".
//
//  Shows what fits, with the reason attached. "Show Everything" opens the rest,
//  including the refusals and why — because the parent always gets to choose,
//  and a refusal you cannot inspect is just a wall.

import SwiftUI

final class PickPresenter: ObservableObject {
    @Published var selectedViewerIds: Set<UUID>
    @Published var showEverything = false
    @Published private(set) var offers: [(title: Title, result: SuitabilityResult)] = []
    @Published private(set) var rest: [(title: Title, result: SuitabilityResult)] = []
    @Published var wizardTitleId: UUID?

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
        selectedViewerIds = Set(store.viewers.map(\.id))
        refresh()
    }

    var allViewers: [Viewer] { store.viewers }
    var viewers: [Viewer] { store.viewers.filter { selectedViewerIds.contains($0.id) } }
    var window: EveningWindow { SuitabilityService(store: store).window(for: viewers) }

    func toggle(_ viewer: Viewer) {
        if selectedViewerIds.contains(viewer.id) {
            selectedViewerIds.remove(viewer.id)
        } else {
            selectedViewerIds.insert(viewer.id)
        }
        NestHaptics.tap()
        refresh()
    }

    func refresh() {
        let ranked = SuitabilityService(store: store).rank(viewers: viewers)
        offers = ranked.filter { $0.result.status.isOffer }
        rest = ranked.filter { !$0.result.status.isOffer }
    }
}

struct PickTonightView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter = PickPresenter(store: .shared)

    var body: some View {
        NestScreen(bottomInset: NestSpace.huge) {
            PageTitle(title: "Fits Tonight",
                      subtitle: "Checked against the people you tick, the window you have, and your own rules.")

            viewerRow

            windowCard

            if store.activeTitles.isEmpty {
                NestCard {
                    EmptyStateView(title: "Nothing to Watch Yet",
                                   message: "Add a few films and the app will work out which ones fit tonight, and which ones fit this child.",
                                   primaryTitle: "Add Title",
                                   primaryAction: { router.openLibraryAdd() })
                }
            } else if presenter.viewers.isEmpty {
                NestCard {
                    EmptyStateView(title: "Nobody Selected",
                                   message: "Tick at least one viewer — the whole point is that the check is about someone in particular.")
                }
            } else {
                offersSection
                everythingSection
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.refresh() }
        .onReceive(store.$document.dropFirst()) { _ in presenter.refresh() }
        .sheet(item: Binding(
            get: { presenter.wizardTitleId.map(IdentifiedUUID.init) },
            set: { presenter.wizardTitleId = $0?.id }
        )) { wrapper in
            EveningWizardView(prefilledTitleId: wrapper.id,
                              prefilledViewerIds: Array(presenter.selectedViewerIds)) {
                presenter.wizardTitleId = nil
            } onCancel: {
                presenter.wizardTitleId = nil
            }
        }
    }

    private var viewerRow: some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            SectionLabel("watching tonight")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NestSpace.l) {
                    ForEach(presenter.allViewers) { viewer in
                        Button { presenter.toggle(viewer) } label: {
                            ViewerToken(viewer: viewer, size: 44,
                                        selected: presenter.selectedViewerIds.contains(viewer.id),
                                        showName: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var windowCard: some View {
        NestPanel(label: "tonight’s window", glow: true) {
            WindowGauge(title: "for the film",
                        minutes: presenter.window.filmMinutes,
                        caption: presenter.window.sentence,
                        fraction: Double(presenter.window.filmMinutes) / Double(max(1, presenter.window.minutesToBedtime)),
                        filmFraction: nil,
                        overflow: presenter.window.filmMinutes == 0)
        }
    }

    private var offersSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Fits Tonight",
                        subtitle: presenter.offers.isEmpty ? nil : "Why this one, in a line.")

            if presenter.offers.isEmpty {
                NestCard {
                    EmptyStateView(title: "Nothing Fits Right Now",
                                   message: "Everything is held back by the window, a rule, an age or a sensitivity. Open Show Everything to see each refusal and pick anyway.",
                                   primaryTitle: "Show Everything",
                                   primaryAction: { withAnimation(NestMotion.base) { presenter.showEverything = true } })
                }
            } else {
                ForEach(Array(presenter.offers.enumerated()), id: \.element.title.id) { index, entry in
                    PickCard(title: entry.title, result: entry.result) {
                        presenter.wizardTitleId = entry.title.id
                    }
                    .nestRise(index)
                }
            }
        }
    }

    private var everythingSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            Button {
                NestHaptics.tap()
                withAnimation(NestMotion.base) { presenter.showEverything.toggle() }
            } label: {
                HStack {
                    Text(presenter.showEverything ? "Hide the rest" : "Show Everything")
                        .font(NestFont.heading)
                        .foregroundColor(NestColor.ink)
                    Spacer()
                    Text("\(presenter.rest.count)")
                        .font(NestFont.figureSmall)
                        .foregroundColor(NestColor.inkFaint)
                    Chevron()
                        .rotationEffect(.degrees(presenter.showEverything ? 90 : 0))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, NestSpace.l)
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

            if presenter.showEverything {
                Text("Everything else, with the reason it is not being offered. You can still choose any of them.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(presenter.rest.enumerated()), id: \.element.title.id) { index, entry in
                    PickCard(title: entry.title, result: entry.result) {
                        presenter.wizardTitleId = entry.title.id
                    }
                    .nestRise(index)
                }
            }
        }
    }
}

struct PickCard: View {
    let title: Title
    let result: SuitabilityResult
    let onAdd: () -> Void

    @AppStorage(NestDefaults.showPosters) private var showPosters: Bool = true

    var body: some View {
        NestCard(padding: NestSpace.m) {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                HStack(alignment: .top, spacing: NestSpace.m) {
                    PosterView(title: title, width: 66, showPoster: showPosters)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top) {
                            Text(title.name)
                                .font(NestFont.titleTight)
                                .foregroundColor(NestColor.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: NestSpace.xs)
                            StatusPill(status: result.status, compact: true)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            SectionLabel("why this one")
                            Text(result.headline)
                                .font(NestFont.body)
                                .foregroundColor(NestColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let changes = result.changesWhen {
                                Text(changes)
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if let split = result.splitSuggestion, !result.fitsWindow {
                    HStack(spacing: NestSpace.s) {
                        ReasonSymbolGlyph(symbol: .split, tint: NestColor.plum, size: 16)
                        Text("Split Over Two Evenings — \(split.first) minutes tonight, \(split.second) next time.")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.plum)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: NestSpace.m) {
                    NavigationLink(destination: SuitabilityView(titleId: title.id)) {
                        Text("Why This One")
                            .font(NestFont.smallMedium)
                            .foregroundColor(NestColor.amberSunk)
                    }
                    Spacer()
                    Button("Add to Evening") {
                        NestHaptics.tap()
                        onAdd()
                    }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.ink))
                }
            }
        }
    }
}
