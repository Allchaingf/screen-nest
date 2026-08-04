//  InsightsModule.swift
//  Screen Nest — Insights.
//
//  Built only from evenings that actually happened. Under three, the screen
//  says so plainly instead of drawing an empty chart with nothing behind it.

import SwiftUI

final class InsightsPresenter: ObservableObject {
    @Published private(set) var insights: [Insight] = []
    @Published var expanded: Set<String> = []
    @Published var toast: NestToast?

    private let store: DataStore
    init(store: DataStore) {
        self.store = store
        refresh()
    }

    var completedCount: Int { InsightsEngine.completed(store.document).count }
    var canBuild: Bool { InsightsEngine.canBuild(store.document) }
    var remainingNeeded: Int { max(0, InsightsEngine.minimumEvenings - completedCount) }

    func refresh() {
        insights = InsightsEngine.build(store.document)
    }

    func evenings(_ ids: [UUID]) -> [Evening] {
        let unique = Array(Set(ids))
        return unique.compactMap { store.evening(id: $0) }.sorted { $0.date > $1.date }
    }

    func perform(_ action: InsightAction) {
        switch action {
        case .markGrownOut(let viewerId, let sensitivityId, let name, let aspect):
            store.markSensitivityGrownOut(viewerId: viewerId, sensitivityId: sensitivityId)
            NestHaptics.success()
            show(NestToast(message: "\(aspect.title) marked grown out of for \(name)"))
            refresh()
        case .openTitle:
            break
        }
    }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter = InsightsPresenter(store: .shared)

    var body: some View {
        NavigationView {
            ZStack {
                NestScreen {
                    PageTitle(title: "Insights",
                              subtitle: "What actually works in this house, from evenings that actually happened.")

                    if !store.isLoaded {
                        LoadingStateView(message: "Reading your evenings…")
                    } else if let error = store.loadError {
                        ErrorStateView(title: "Could not read your evenings",
                                       message: error, retryTitle: "Reload") {
                            store.load()
                            presenter.refresh()
                        }
                    } else if !presenter.canBuild {
                        notEnoughYet
                    } else if presenter.insights.isEmpty {
                        NestCard {
                            EmptyStateView(title: "Nothing to Report Yet",
                                           message: "Your evenings are recorded, but none of them carry enough detail to draw a conclusion from. Recording reactions is what makes this page work.")
                        }
                    } else {
                        ForEach(presenter.insights) { insight in
                            InsightCard(insight: insight,
                                        expanded: presenter.expanded.contains(insight.id),
                                        evenings: presenter.evenings(insight.eveningIds),
                                        store: store,
                                        onToggle: {
                                withAnimation(NestMotion.base) {
                                    if presenter.expanded.contains(insight.id) {
                                        presenter.expanded.remove(insight.id)
                                    } else {
                                        presenter.expanded.insert(insight.id)
                                    }
                                }
                            }, onAction: { action in
                                presenter.perform(action)
                            })
                        }
                    }
                }
                ToastOverlay(toast: presenter.toast)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear { presenter.refresh() }
        .onReceive(store.$document.dropFirst()) { _ in presenter.refresh() }
    }

    private var notEnoughYet: some View {
        NestCard(glow: true) {
            VStack(alignment: .leading, spacing: NestSpace.l) {
                SectionLabel("more evenings needed")
                Text("More Evenings Needed")
                    .font(NestFont.displaySmall)
                    .foregroundColor(NestColor.ink)
                Text("Complete at least three evenings to see what actually works in your house.")
                    .font(NestFont.body)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                WindowBar(fraction: Double(presenter.completedCount) / Double(InsightsEngine.minimumEvenings),
                          height: 12)

                Text("\(presenter.completedCount) of \(InsightsEngine.minimumEvenings) recorded. \(presenter.remainingNeeded) to go.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)

                Text("Nothing is invented here in the meantime — a chart drawn from one evening would be a guess wearing a graph.")
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Plan an Evening") { router.openWizard() }
            }
        }
    }
}

struct InsightCard: View {
    let insight: Insight
    let expanded: Bool
    let evenings: [Evening]
    let store: DataStore
    let onToggle: () -> Void
    let onAction: (InsightAction) -> Void

    var body: some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                SectionLabel(insight.title)

                Text(insight.headline)
                    .font(NestFont.title)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.detail)
                    .font(NestFont.small)
                    .foregroundColor(NestColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.bars.isEmpty {
                    VStack(alignment: .leading, spacing: NestSpace.s) {
                        ForEach(insight.bars) { bar in
                            InsightBarRow(bar: bar)
                        }
                    }
                    .padding(.top, NestSpace.xs)
                }

                if let action = insight.action, case .markGrownOut = action {
                    Button(action.title) {
                        NestHaptics.tap()
                        onAction(action)
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: NestColor.go))
                }

                if let action = insight.action, case .openTitle(let titleId, let name) = action {
                    NavigationLink(destination: TitleDetailView(titleId: titleId)) {
                        Text("Open \(name)")
                            .font(NestFont.smallMedium)
                            .foregroundColor(NestColor.amberSunk)
                    }
                }

                if !evenings.isEmpty {
                    Button {
                        NestHaptics.tap()
                        onToggle()
                    } label: {
                        HStack {
                            Text(expanded ? "Hide related evenings" : "View Related Evenings")
                                .font(NestFont.smallMedium)
                                .foregroundColor(NestColor.amberSunk)
                            Spacer()
                            Text("\(evenings.count)")
                                .font(NestFont.figureMicro)
                                .foregroundColor(NestColor.inkFaint)
                            Chevron().rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    if expanded {
                        VStack(alignment: .leading, spacing: NestSpace.s) {
                            ForEach(evenings) { evening in
                                NavigationLink(destination: EveningRecapView(eveningId: evening.id)) {
                                    HStack(spacing: NestSpace.m) {
                                        Text(TimeFormat.shortDayFormatter.string(from: evening.date))
                                            .font(NestFont.figureMicro)
                                            .foregroundColor(NestColor.inkFaint)
                                            .frame(width: 84, alignment: .leading)
                                        Text(evening.titleSnapshot?.name ?? evening.displayName)
                                            .font(NestFont.small)
                                            .foregroundColor(NestColor.ink)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Chevron()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, NestSpace.xs)
                    }
                }
            }
        }
    }
}

/// Bars are drawn from the app's own texture — a filled window strip with the
/// tick scale above it, never a stock chart.
struct InsightBarRow: View {
    let bar: InsightBar

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.label)
                    .font(bar.highlighted ? NestFont.bodyMedium : NestFont.small)
                    .foregroundColor(bar.highlighted ? NestColor.ink : NestColor.inkSoft)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: NestSpace.s)
                if !bar.caption.isEmpty {
                    Text(bar.caption)
                        .font(NestFont.figureMicro)
                        .foregroundColor(NestColor.inkFaint)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NestColor.surfaceSunk)
                        .frame(height: 8)
                    Capsule()
                        .fill(bar.highlighted ? NestColor.amber : NestColor.amber.opacity(0.42))
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, bar.fraction)))), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}
