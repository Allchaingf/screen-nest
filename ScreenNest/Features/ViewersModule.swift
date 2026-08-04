//  ViewersModule.swift
//  Screen Nest — viewers, house rules and screen time live under this tab.

import SwiftUI

final class ViewersPresenter: ObservableObject {
    @Published var showForm = false
    @Published var editing: Viewer?
    @Published var toast: NestToast?

    private let store: DataStore
    init(store: DataStore) { self.store = store }

    var viewers: [Viewer] { store.viewers }
    var children: [Viewer] { store.children }
    var adults: [Viewer] { store.adults }
    var ruleCount: Int { store.activeRules.count }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct ViewersView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter = ViewersPresenter(store: .shared)

    var body: some View {
        NavigationView {
            ZStack {
                NestScreen {
                    header
                    shortcuts
                    if !store.isLoaded {
                        LoadingStateView(message: "Reading the household…")
                    } else if let error = store.loadError {
                        ErrorStateView(title: "Could not read your viewers",
                                       message: error, retryTitle: "Reload") { store.load() }
                    } else if presenter.viewers.isEmpty {
                        NestCard {
                            EmptyStateView(title: "Nobody Here Yet",
                                           message: "A rating says “10+”. It does not know that this child cannot watch an animal get hurt. Add the people who actually watch, and the app can start being useful.",
                                           primaryTitle: "Add Viewer",
                                           primaryAction: { openAdd() })
                        }
                    } else {
                        list
                    }
                }
                ToastOverlay(toast: presenter.toast)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if router.viewersOpensAddForm {
                router.viewersOpensAddForm = false
                openAdd()
            }
        }
        .onChange(of: router.viewersOpensAddForm) { open in
            if open {
                router.viewersOpensAddForm = false
                openAdd()
            }
        }
        .sheet(isPresented: $presenter.showForm, onDismiss: { presenter.editing = nil }) {
            ViewerFormView(viewer: presenter.editing,
                           existingCount: store.viewers.count,
                           allowDelete: presenter.editing != nil,
                           onSave: { viewer in
                store.upsertViewer(viewer)
                presenter.showForm = false
                presenter.show(NestToast(message: "Viewer saved"))
            }, onDelete: { id in
                store.deleteViewer(id: id)
                presenter.showForm = false
                presenter.show(NestToast(message: "Viewer removed"))
            }, onCancel: {
                presenter.showForm = false
            })
        }
    }

    private func openAdd() {
        presenter.editing = nil
        presenter.showForm = true
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageTitle(title: "Viewers",
                      subtitle: "Everyone who watches, with what lands well and what does not — yet.")
            Spacer()
            Button {
                NestHaptics.tap()
                openAdd()
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
            .accessibilityLabel("Add viewer")
        }
    }

    private var shortcuts: some View {
        NestRowGroup {
            NavigationLink(destination: HouseRulesView()) {
                NestRow(title: "House Rules",
                        subtitle: "\(presenter.ruleCount) active rule\(presenter.ruleCount == 1 ? "" : "s")",
                        trailing: { Chevron() }, action: nil)
            }
            .buttonStyle(.plain)

            RowDivider()

            NavigationLink(destination: ScreenTimeView()) {
                NestRow(title: "Screen Time",
                        subtitle: "Weekly minutes, counted from what was actually watched",
                        trailing: { Chevron() }, action: nil)
            }
            .buttonStyle(.plain)

            RowDivider()

            NavigationLink(destination: ContentNotesView()) {
                NestRow(title: "Content Notes",
                        subtitle: "\(store.contentNotes.count) note\(store.contentNotes.count == 1 ? "" : "s") recorded here",
                        trailing: { Chevron() }, action: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: NestSpace.xl) {
            if !presenter.children.isEmpty {
                group(title: "Children and Teenagers", viewers: presenter.children)
            }
            if !presenter.adults.isEmpty {
                group(title: "Adults", viewers: presenter.adults)
            }
        }
    }

    private func group(title: String, viewers: [Viewer]) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead(title)
            ForEach(viewers) { viewer in
                Button {
                    NestHaptics.tap()
                    presenter.editing = viewer
                    presenter.showForm = true
                } label: {
                    ViewerCard(viewer: viewer,
                               week: ScreenTimeEngine.week(for: viewer, in: store.document),
                               onGrownOut: { record in
                        store.markSensitivityGrownOut(viewerId: viewer.id, sensitivityId: record.id)
                        presenter.show(NestToast(message: "\(record.aspect.title) marked grown out of"))
                    })
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ViewerCard: View {
    let viewer: Viewer
    let week: ScreenTimeWeek
    let onGrownOut: (SensitivityRecord) -> Void

    var body: some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                HStack(alignment: .top, spacing: NestSpace.m) {
                    ViewerToken(viewer: viewer, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewer.name)
                            .font(NestFont.titleTight)
                            .foregroundColor(NestColor.ink)
                        Text(subtitle)
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                    }
                    Spacer()
                    Chevron()
                }

                if !viewer.activeSensitivities.isEmpty {
                    VStack(alignment: .leading, spacing: NestSpace.s) {
                        SectionLabel("sensitive to")
                        ChipFlow(items: viewer.activeSensitivities.map(\.aspect)) { aspect in
                            NestChip(title: aspect.title, selected: true,
                                     tint: NestColor.stop, glyph: aspect)
                        }
                        if let oldest = viewer.activeSensitivities.min(by: { $0.addedOn < $1.addedOn }) {
                            Button {
                                NestHaptics.tap()
                                onGrownOut(oldest)
                            } label: {
                                Text("Mark Grown Out Of — \(oldest.aspect.title)")
                                    .font(NestFont.smallMedium)
                                    .foregroundColor(NestColor.go)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if !viewer.role.isGrownUp {
                    HStack(spacing: NestSpace.s) {
                        ReasonSymbolGlyph(symbol: .unknown, tint: NestColor.amberSunk, size: 16)
                        Text("Tell me what scares \(viewer.name) — without it, the check is only about age.")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.amberSunk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !viewer.retiredSensitivities.isEmpty {
                    VStack(alignment: .leading, spacing: NestSpace.s) {
                        SectionLabel("grown out of")
                        ChipFlow(items: viewer.retiredSensitivities.map(\.aspect)) { aspect in
                            NestChip(title: aspect.title, selected: false, glyph: aspect)
                        }
                    }
                }

                if !viewer.loves.isEmpty {
                    VStack(alignment: .leading, spacing: NestSpace.s) {
                        SectionLabel("loves")
                        ChipFlow(items: viewer.loves) { love in
                            NestChip(title: love, selected: true, tint: NestColor.go)
                        }
                    }
                }

                if week.limitMinutes != nil {
                    ScreenTimeStrip(week: week)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [viewer.role.title]
        if let age = viewer.age { parts.append("\(age) years old") }
        parts.append("\(viewer.attentionSpanMinutes) min at a time")
        if let bedtime = viewer.bedtimeOverride { parts.append("bed \(bedtime.display)") }
        return parts.joined(separator: " · ")
    }
}
