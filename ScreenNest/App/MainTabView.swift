//  MainTabView.swift
//  Screen Nest — the shell.
//
//  Five sections on a "lamp shelf": a cream bar under a tick rule, where the
//  active section sits in a soft amber glow and its label darkens. Labels are
//  always visible; the glyphs are drawn, not borrowed.

import SwiftUI

enum MainTab: Int, CaseIterable, Identifiable {
    case home, library, evenings, viewers, insights
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .evenings: return "Evenings"
        case .viewers: return "Viewers"
        case .insights: return "Insights"
        }
    }
}

/// Shared navigation intents that cross tab boundaries.
final class AppRouter: ObservableObject {
    @Published var tab: MainTab = .home
    @Published var libraryOpensAddForm = false
    @Published var viewersOpensAddForm = false
    @Published var eveningsOpensWizard = false
    @Published var watchEveningId: UUID?
    @Published var afterWatchEveningId: UUID?
    @Published var showSettings = false

    func openLibraryAdd() {
        tab = .library
        libraryOpensAddForm = true
    }

    func openViewerAdd() {
        tab = .viewers
        viewersOpensAddForm = true
    }

    func openWizard() {
        tab = .evenings
        eveningsOpensWizard = true
    }

    func openWatch(_ eveningId: UUID) {
        watchEveningId = eveningId
    }

    func openAfterWatch(_ eveningId: UUID) {
        watchEveningId = nil
        afterWatchEveningId = eveningId
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack(alignment: .bottom) {
            NestColor.ground.ignoresSafeArea()

            Group {
                switch router.tab {
                case .home:     HomeView()
                case .library:  LibraryView()
                case .evenings: EveningsView()
                case .viewers:  ViewersView()
                case .insights: InsightsView()
                }
            }
            .environmentObject(router)

            LampShelf(selection: $router.tab)
        }
        .fullScreenCover(item: Binding(
            get: { router.watchEveningId.map(IdentifiedUUID.init) },
            set: { router.watchEveningId = $0?.id }
        )) { wrapper in
            WatchModeView(eveningId: wrapper.id)
                .environmentObject(store)
                .environmentObject(router)
        }
        .sheet(item: Binding(
            get: { router.afterWatchEveningId.map(IdentifiedUUID.init) },
            set: { router.afterWatchEveningId = $0?.id }
        )) { wrapper in
            AfterWatchView(eveningId: wrapper.id) {
                router.afterWatchEveningId = nil
            }
            .environmentObject(store)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView { router.showSettings = false }
                .environmentObject(store)
        }
    }
}

/// Small wrapper so a UUID can drive `sheet(item:)`.
struct IdentifiedUUID: Identifiable {
    let id: UUID
    init(_ id: UUID) { self.id = id }
}

// MARK: - The shelf
//
// A solid anchor-ink bar under a dotted amber line. The active section sits on
// an amber pill that slides between tabs on a spring — the active state is a
// fill, never a colour change alone.

struct LampShelf: View {
    @Binding var selection: MainTab
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 0) {
            DottedRule(colour: NestColor.amberTop, dot: 3, spacing: 8)
                .padding(.bottom, 0)

            HStack(spacing: 0) {
                ForEach(MainTab.allCases) { tab in
                    ShelfCell(tab: tab, active: tab == selection, namespace: pill) {
                        guard selection != tab else { return }
                        NestHaptics.tap()
                        withAnimation(NestMotion.tabPill) { selection = tab }
                    }
                }
            }
            .padding(.horizontal, NestSpace.s)
            .padding(.top, NestSpace.m)
            .frame(height: 88, alignment: .top)
        }
        .background(
            NestColor.anchorSolid.ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct ShelfCell: View {
    let tab: MainTab
    let active: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                TabGlyph(tab: tab)
                    .stroke(active ? NestColor.inkOnAmber : Color(nestHex: 0xFFF3DC).opacity(0.60),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)

                nestTracked(tab.title.uppercased(), kern: 0.5)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(active ? NestColor.inkOnAmber : Color(nestHex: 0xFFF3DC).opacity(0.60))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if active {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(NestColor.amberGradient)
                            .matchedGeometryEffect(id: "tabPill", in: namespace)
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Domain glyphs, drawn: a nest, a shelf of spines, a window bar, tokens, a rule.
struct TabGlyph: Shape {
    let tab: MainTab

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()

        switch tab {
        case .home:
            path.move(to: p(0.08, 0.52))
            path.addQuadCurve(to: p(0.92, 0.52), control: p(0.50, 1.02))
            path.addRoundedRect(in: CGRect(x: 0.22 * s, y: 0.14 * s, width: 0.56 * s, height: 0.40 * s),
                                cornerSize: CGSize(width: 0.10 * s, height: 0.10 * s))

        case .library:
            for (index, x) in [0.16, 0.36, 0.56].enumerated() {
                let top = 0.18 + CGFloat(index) * 0.06
                path.addRoundedRect(in: CGRect(x: CGFloat(x) * s, y: top * s,
                                               width: 0.14 * s, height: (0.82 - top) * s),
                                    cornerSize: CGSize(width: 0.04 * s, height: 0.04 * s))
            }
            path.move(to: p(0.78, 0.24))
            path.addLine(to: p(0.78, 0.82))

        case .evenings:
            path.addRoundedRect(in: CGRect(x: 0.10 * s, y: 0.40 * s, width: 0.80 * s, height: 0.20 * s),
                                cornerSize: CGSize(width: 0.10 * s, height: 0.10 * s))
            path.addRoundedRect(in: CGRect(x: 0.10 * s, y: 0.40 * s, width: 0.46 * s, height: 0.20 * s),
                                cornerSize: CGSize(width: 0.10 * s, height: 0.10 * s))
            for x in [0.16, 0.36, 0.56, 0.76] {
                path.move(to: p(CGFloat(x), 0.22))
                path.addLine(to: p(CGFloat(x), 0.31))
            }

        case .viewers:
            path.addEllipse(in: CGRect(x: 0.08 * s, y: 0.30 * s, width: 0.30 * s, height: 0.30 * s))
            path.addEllipse(in: CGRect(x: 0.38 * s, y: 0.18 * s, width: 0.26 * s, height: 0.26 * s))
            path.addEllipse(in: CGRect(x: 0.62 * s, y: 0.34 * s, width: 0.26 * s, height: 0.26 * s))
            path.move(to: p(0.14, 0.82))
            path.addLine(to: p(0.86, 0.82))

        case .insights:
            path.move(to: p(0.12, 0.84))
            path.addLine(to: p(0.88, 0.84))
            for (index, h) in [0.30, 0.52, 0.20, 0.62].enumerated() {
                let x = 0.20 + CGFloat(index) * 0.18
                path.move(to: p(x, 0.80))
                path.addLine(to: p(x, 0.80 - CGFloat(h)))
            }
        }
        return path
    }
}
