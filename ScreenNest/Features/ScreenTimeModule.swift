//  ScreenTimeModule.swift
//  Screen Nest — screen time.
//
//  Counts only what was actually watched. Shows the remainder and offers three
//  ways forward. It never blocks, never scolds and never suggests what the
//  limit ought to be — the family sets it.

import SwiftUI

final class ScreenTimePresenter: ObservableObject {
    @Published var showHistory = false
    @Published var allowExtraFor: UUID?
    @Published var extraMinutes: Int = 30
    @Published var extraReason: String = ""
    @Published var editingLimitFor: UUID?
    @Published var toast: NestToast?

    private let store: DataStore
    init(store: DataStore) { self.store = store }

    var weeks: [ScreenTimeWeek] { ScreenTimeEngine.allWeeks(in: store.document) }
    var children: [Viewer] { store.children }

    func entries(for viewerId: UUID) -> [ScreenTimeEntry] {
        ScreenTimeEngine.entries(viewerId: viewerId, in: store.document, weekOf: Date())
    }

    func history(for viewer: Viewer) -> [ScreenTimeWeek] {
        ScreenTimeEngine.history(for: viewer, in: store.document)
    }

    func allowExtra() {
        guard let viewerId = allowExtraFor else { return }
        let exception = ScreenTimeException(viewerId: viewerId,
                                            weekStart: ScreenTimeEngine.weekStart(for: Date()),
                                            extraMinutes: extraMinutes,
                                            reason: extraReason.trimmingCharacters(in: .whitespaces))
        store.addScreenTimeException(exception)
        allowExtraFor = nil
        extraReason = ""
        extraMinutes = 30
        NestHaptics.success()
        show(NestToast(message: "Extra time allowed"))
    }

    func setLimit(viewerId: UUID, minutes: Int?, rollover: Bool) {
        guard var viewer = store.viewer(id: viewerId) else { return }
        viewer.weeklyLimitMinutes = minutes
        viewer.rolloverAllowed = rollover
        store.upsertViewer(viewer)
        show(NestToast(message: "Limit saved"))
    }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct ScreenTimeView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter = ScreenTimePresenter(store: .shared)

    var body: some View {
        ZStack {
            NestScreen(bottomInset: NestSpace.huge) {
                PageTitle(title: "Screen Time",
                          subtitle: "This Week · counted from what was actually watched, not what was planned.")

                if presenter.children.isEmpty {
                    NestCard {
                        EmptyStateView(title: "No Children Added",
                                       message: "Screen time is kept per child. Add one in Viewers and set a weekly limit there or here.",
                                       primaryTitle: "Add Viewer",
                                       primaryAction: { router.openViewerAdd() })
                    }
                } else if presenter.weeks.allSatisfy({ $0.limitMinutes == nil }) {
                    NestCard {
                        EmptyStateView(title: "No Limits Being Kept",
                                       message: "Set a weekly limit for a child and the remainder appears here and on Home. The app shows it and nothing else — the number is yours.")
                    }
                    limitEditors
                } else {
                    ForEach(presenter.weeks) { week in
                        weekCard(week)
                    }
                    limitEditors
                }

                Text("Screen Nest does not recommend how much screen time is right. It only keeps the count you asked for.")
                    .font(NestFont.micro)
                    .foregroundColor(NestColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, NestSpace.s)
            }
            ToastOverlay(toast: presenter.toast)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { presenter.allowExtraFor.map(IdentifiedUUID.init) },
            set: { presenter.allowExtraFor = $0?.id }
        )) { wrapper in
            allowExtraSheet(viewerId: wrapper.id)
        }
    }

    private func weekCard(_ week: ScreenTimeWeek) -> some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                ScreenTimeStrip(week: week)

                if let remaining = week.remainingMinutes {
                    if remaining < 0 {
                        Text("\(week.viewerName) is \(-remaining) minutes over the limit you set for this week.")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.stop)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let shortest = shortestRuntime, remaining < shortest {
                        VStack(alignment: .leading, spacing: NestSpace.s) {
                            Text("\(week.viewerName) has \(remaining) minutes left this week. The shortest thing in your library is \(shortest).")
                                .font(NestFont.small)
                                .foregroundColor(NestColor.amberSunk)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: NestSpace.s) {
                                Button("Split Over Two Evenings") {
                                    NestHaptics.tap()
                                    router.openWizard()
                                }
                                .buttonStyle(QuietButtonStyle(tint: NestColor.plum))
                                Button("Choose Something Shorter") {
                                    NestHaptics.tap()
                                    router.tab = .library
                                }
                                .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                            }
                        }
                    }
                }

                let entries = presenter.entries(for: week.viewerId)
                if entries.isEmpty {
                    Text("Nothing watched yet this week.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkFaint)
                } else {
                    VStack(alignment: .leading, spacing: NestSpace.s) {
                        SectionLabel("this week")
                        ForEach(entries) { entry in
                            HStack {
                                Text(entry.titleName)
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.ink)
                                Spacer()
                                Text("\(entry.minutes) min")
                                    .font(NestFont.figureMicro)
                                    .foregroundColor(NestColor.inkSoft)
                            }
                        }
                    }
                }

                if week.extraMinutes > 0 {
                    Text("\(week.extraMinutes) extra minutes allowed this week.")
                        .font(NestFont.micro)
                        .foregroundColor(NestColor.plum)
                }

                HStack(spacing: NestSpace.m) {
                    Button("Allow Extra") {
                        NestHaptics.tap()
                        presenter.allowExtraFor = week.viewerId
                    }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.plum))
                    Spacer()
                    Button(presenter.showHistory ? "Hide History" : "History") {
                        NestHaptics.tap()
                        withAnimation(NestMotion.base) { presenter.showHistory.toggle() }
                    }
                    .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                }

                if presenter.showHistory, let viewer = store.viewer(id: week.viewerId) {
                    historyStrip(for: viewer)
                }
            }
        }
    }

    private var shortestRuntime: Int? {
        store.activeTitles.map(\.runtimeMinutes).filter { $0 > 0 }.min()
    }

    private func historyStrip(for viewer: Viewer) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            SectionLabel("previous weeks")
            let weeks = presenter.history(for: viewer)
            let maximum = max(1, weeks.map(\.usedMinutes).max() ?? 1)
            HStack(alignment: .bottom, spacing: NestSpace.s) {
                ForEach(weeks.reversed()) { week in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(week.isOver ? NestColor.stop : NestColor.amber)
                            .frame(width: 18, height: max(3, CGFloat(week.usedMinutes) / CGFloat(maximum) * 62))
                        Text(weekLabel(week.weekStart))
                            .font(NestFont.micro)
                            .foregroundColor(NestColor.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 84, alignment: .bottom)
        }
    }

    private func weekLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d/M"
        return f.string(from: date)
    }

    private var limitEditors: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Set Limit", subtitle: "Per child, per week.")
            ForEach(presenter.children) { viewer in
                LimitEditor(viewer: viewer) { minutes, rollover in
                    presenter.setLimit(viewerId: viewer.id, minutes: minutes, rollover: rollover)
                }
            }
        }
    }

    private func allowExtraSheet(viewerId: UUID) -> some View {
        let name = store.viewer(id: viewerId)?.name ?? "this viewer"
        return SheetScaffold(title: "Allow Extra This Once",
                             subtitle: "For \(name), this week only.",
                             closeTitle: "Cancel",
                             onClose: { presenter.allowExtraFor = nil }) {
            FieldShell(label: "Extra Minutes") {
                NestSlider(value: $presenter.extraMinutes, range: 5...240, step: 5, suffix: "min")
            }
            FieldShell(label: "Reason", hint: "Kept with the week so you can see why later.") {
                NestTextField(placeholder: "e.g. sick day", text: $presenter.extraReason)
            }
            PrimaryButton(title: "Allow \(presenter.extraMinutes) Minutes") {
                presenter.allowExtra()
            }
        }
    }
}

struct LimitEditor: View {
    let viewer: Viewer
    let onSave: (Int?, Bool) -> Void

    @State private var enabled: Bool
    @State private var minutes: Int
    @State private var rollover: Bool

    init(viewer: Viewer, onSave: @escaping (Int?, Bool) -> Void) {
        self.viewer = viewer
        self.onSave = onSave
        _enabled = State(initialValue: viewer.weeklyLimitMinutes != nil)
        _minutes = State(initialValue: viewer.weeklyLimitMinutes ?? 420)
        _rollover = State(initialValue: viewer.rolloverAllowed)
    }

    var body: some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                HStack(spacing: NestSpace.m) {
                    ViewerToken(viewer: viewer, size: 34)
                    Text(viewer.name)
                        .font(NestFont.titleTight)
                        .foregroundColor(NestColor.ink)
                    Spacer()
                }
                NestToggleRow(title: "Keep a weekly limit", isOn: $enabled)
                if enabled {
                    NestSlider(value: $minutes, range: 0...1200, step: 30, suffix: "min / week")
                    NestToggleRow(title: "Rollover Allowed",
                                  subtitle: "Unused minutes carry into next week.",
                                  isOn: $rollover)
                }
                PrimaryButton(title: "Save Limit") {
                    onSave(enabled ? minutes : nil, rollover)
                }
            }
        }
    }
}
