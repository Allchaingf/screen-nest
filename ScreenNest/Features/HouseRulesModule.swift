//  HouseRulesModule.swift
//  Screen Nest — house rules and their history.
//
//  A rule can be broken on purpose. The app records the reason rather than
//  standing in the way, and keeps the history so you can see how the boundaries
//  moved as the children grew.

import SwiftUI

final class HouseRulesPresenter: ObservableObject {
    @Published var showForm = false
    @Published var editing: HouseRule?
    @Published var showHistory = false
    @Published var toast: NestToast?

    private let store: DataStore
    init(store: DataStore) { self.store = store }

    var active: [HouseRule] { store.rules.filter(\.isActive) }
    var retired: [HouseRule] { store.rules.filter { !$0.isActive } }
    var history: [RuleHistoryEntry] { store.document.ruleHistory.sorted { $0.date > $1.date } }
    var exceptions: [(evening: Evening, exception: RuleException)] {
        store.evenings.flatMap { evening in evening.exceptions.map { (evening, $0) } }
            .sorted { $0.1.date > $1.1.date }
    }
    var viewers: [Viewer] { store.viewers }
    var country: RatingCountry { store.profile.ratingCountry }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct HouseRulesView: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter = HouseRulesPresenter(store: .shared)

    var body: some View {
        ZStack {
            NestScreen(bottomInset: NestSpace.huge) {
                PageTitle(title: "House Rules",
                          subtitle: "These sit above any certificate. Nothing is ever forbidden — an exception simply gets written down.")

                if presenter.active.isEmpty && presenter.retired.isEmpty {
                    NestCard {
                        EmptyStateView(title: "No Rules Yet",
                                       message: "A rule is how you say what is true in this house, whatever a certificate claims.",
                                       primaryTitle: "Add Rule",
                                       primaryAction: { openAdd() })
                    }
                } else {
                    activeSection
                    if !presenter.retired.isEmpty { retiredSection }
                    if !presenter.exceptions.isEmpty { exceptionsSection }
                    historySection
                }

                PrimaryButton(title: "Add Rule") { openAdd() }
                    .padding(.top, NestSpace.s)
            }
            ToastOverlay(toast: presenter.toast)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $presenter.showForm, onDismiss: { presenter.editing = nil }) {
            RuleFormView(rule: presenter.editing,
                         viewers: presenter.viewers,
                         country: presenter.country,
                         allowDelete: presenter.editing != nil,
                         onSave: { rule in
                store.upsertRule(rule, changeNote: presenter.editing == nil
                                 ? "Added — \(rule.valueSummary)"
                                 : "Edited — \(rule.valueSummary)")
                presenter.showForm = false
                presenter.show(NestToast(message: "Rule saved"))
            }, onDelete: { id in
                store.deleteRule(id: id)
                presenter.showForm = false
                presenter.show(NestToast(message: "Rule removed"))
            }, onCancel: {
                presenter.showForm = false
            })
        }
    }

    private func openAdd() {
        presenter.editing = nil
        presenter.showForm = true
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Active")
            if presenter.active.isEmpty {
                NestCard {
                    Text("Every rule has been retired. Nothing is being checked against right now.")
                        .font(NestFont.body)
                        .foregroundColor(NestColor.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(presenter.active) { rule in
                ruleCard(rule, active: true)
            }
        }
    }

    private var retiredSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Retired", subtitle: "Kept so you can see how the boundaries moved.")
            ForEach(presenter.retired) { rule in
                ruleCard(rule, active: false)
            }
        }
    }

    private func ruleCard(_ rule: HouseRule, active: Bool) -> some View {
        NestCard(tint: active ? NestColor.surface : NestColor.surfaceSunk) {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                Button {
                    NestHaptics.tap()
                    presenter.editing = rule
                    presenter.showForm = true
                } label: {
                    HStack(alignment: .top, spacing: NestSpace.m) {
                        ReasonSymbolGlyph(symbol: .rule,
                                          tint: active ? NestColor.amberSunk : NestColor.inkFaint,
                                          size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.type.title)
                                .font(NestFont.titleTight)
                                .foregroundColor(active ? NestColor.ink : NestColor.inkFaint)
                                .multilineTextAlignment(.leading)
                            Text(rule.valueSummary)
                                .font(NestFont.small)
                                .foregroundColor(NestColor.inkSoft)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Chevron()
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: NestSpace.s) {
                    NestChip(title: rule.appliesTo.isEmpty
                             ? "Everyone"
                             : store.viewers(ids: rule.appliesTo).map(\.name).joined(separator: ", "),
                             selected: false)
                    if rule.exceptionAllowed {
                        NestChip(title: "Exception allowed", selected: true, tint: NestColor.plum)
                    }
                    Spacer(minLength: 0)
                }

                if !rule.notes.isEmpty {
                    Text(rule.notes)
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    if active {
                        Button("Retire Rule") {
                            NestHaptics.tap()
                            store.retireRule(id: rule.id)
                            presenter.show(NestToast(message: "Rule retired"))
                        }
                        .buttonStyle(QuietButtonStyle(tint: NestColor.stop))
                    } else {
                        Button("Reinstate Rule") {
                            NestHaptics.tap()
                            store.reinstateRule(id: rule.id)
                            presenter.show(NestToast(message: "Rule reinstated"))
                        }
                        .buttonStyle(QuietButtonStyle(tint: NestColor.go))
                    }
                    Spacer()
                }
            }
        }
    }

    private var exceptionsSection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Allowed Exceptions",
                        subtitle: "Rules broken on purpose, with the reason.")
            ForEach(Array(presenter.exceptions.enumerated()), id: \.offset) { _, entry in
                NestCard(padding: NestSpace.m, tint: NestColor.plumWash, stroke: NestColor.plum.opacity(0.35)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rule broken on purpose: \(entry.exception.reason)")
                            .font(NestFont.body)
                            .foregroundColor(NestColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(entry.exception.ruleTitle) · \(TimeFormat.shortDayFormatter.string(from: entry.exception.date)) · \(entry.evening.titleSnapshot?.name ?? entry.evening.displayName)")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            Button {
                NestHaptics.tap()
                withAnimation(NestMotion.base) { presenter.showHistory.toggle() }
            } label: {
                HStack {
                    Text("Rule History")
                        .font(NestFont.heading)
                        .foregroundColor(NestColor.ink)
                    Spacer()
                    Text("\(presenter.history.count)")
                        .font(NestFont.figureSmall)
                        .foregroundColor(NestColor.inkFaint)
                    Chevron().rotationEffect(.degrees(presenter.showHistory ? 90 : 0))
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

            if presenter.showHistory {
                if presenter.history.isEmpty {
                    NestCard {
                        Text("Nothing has changed yet.")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkFaint)
                    }
                } else {
                    NestCard {
                        VStack(alignment: .leading, spacing: NestSpace.m) {
                            ForEach(presenter.history) { entry in
                                HStack(alignment: .top, spacing: NestSpace.m) {
                                    Text(TimeFormat.shortDayFormatter.string(from: entry.date))
                                        .font(NestFont.figureMicro)
                                        .foregroundColor(NestColor.inkFaint)
                                        .frame(width: 88, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.ruleTitle)
                                            .font(NestFont.smallMedium)
                                            .foregroundColor(NestColor.ink)
                                        Text(entry.change)
                                            .font(NestFont.small)
                                            .foregroundColor(NestColor.inkSoft)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
