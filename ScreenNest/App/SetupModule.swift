//  SetupModule.swift
//  Screen Nest — initial setup.
//
//  Cannot be finished without a rating country, at least one viewer and at
//  least one house rule. Everything set here is editable later; evenings that
//  are already finished are never recalculated.

import SwiftUI

// MARK: - Interactor

protocol SetupInteracting {
    func save(profile: HouseProfile, viewers: [Viewer], rules: [HouseRule])
}

struct SetupInteractor: SetupInteracting {
    let store: DataStore

    func save(profile: HouseProfile, viewers: [Viewer], rules: [HouseRule]) {
        store.mutate { document in
            var saved = profile
            saved.setupCompleted = true
            document.profile = saved
            document.viewers = viewers
            document.rules = rules
            document.ruleHistory = rules.map {
                RuleHistoryEntry(ruleId: $0.id, ruleTitle: $0.type.title, change: "Added during setup")
            }
        }
        store.saveNow()
    }
}

// MARK: - Presenter

final class SetupPresenter: ObservableObject {

    @Published var displayName: String = ""
    @Published var country: RatingCountry?
    @Published var weeknightBedtime = TimeOfDay.defaultWeeknight
    @Published var weekendBedtime = TimeOfDay.defaultWeekend
    @Published var weeklyLimit: Int = 420
    @Published var viewers: [Viewer] = []
    @Published var rules: [HouseRule] = []

    @Published var showViewerForm = false
    @Published var editingViewer: Viewer?
    @Published var showRuleForm = false
    @Published var editingRule: HouseRule?
    @Published var attemptedSave = false
    @Published var isSaving = false

    private let interactor: SetupInteracting
    private let onComplete: () -> Void

    init(interactor: SetupInteracting, onComplete: @escaping () -> Void) {
        self.interactor = interactor
        self.onComplete = onComplete
    }

    // MARK: Validation

    var countryError: String? {
        attemptedSave && country == nil ? "Choose the country whose certificates you follow." : nil
    }
    var viewerError: String? {
        attemptedSave && viewers.isEmpty ? "Add at least one viewer — the check has to be about someone." : nil
    }
    var ruleError: String? {
        attemptedSave && rules.isEmpty ? "Add at least one house rule. You can change it whenever you like." : nil
    }

    var canSave: Bool { country != nil && !viewers.isEmpty && !rules.isEmpty }

    var progress: Double {
        var done = 0.0
        if country != nil { done += 1 }
        if !viewers.isEmpty { done += 1 }
        if !rules.isEmpty { done += 1 }
        return done / 3.0
    }

    // MARK: Intents

    func addViewer(_ viewer: Viewer) {
        if let index = viewers.firstIndex(where: { $0.id == viewer.id }) {
            viewers[index] = viewer
        } else {
            var copy = viewer
            copy.colourIndex = viewers.count
            viewers.append(copy)
        }
    }

    func removeViewer(_ id: UUID) {
        viewers.removeAll { $0.id == id }
    }

    func addRule(_ rule: HouseRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func save() {
        attemptedSave = true
        guard canSave, !isSaving, let country = country else {
            NestHaptics.warning()
            return
        }
        isSaving = true

        var profile = HouseProfile()
        profile.displayName = displayName.trimmingCharacters(in: .whitespaces)
        profile.ratingCountry = country
        profile.weeknightBedtime = weeknightBedtime
        profile.weekendBedtime = weekendBedtime
        profile.defaultWeeklyLimitMinutes = weeklyLimit

        interactor.save(profile: profile, viewers: viewers, rules: rules)
        NestHaptics.success()
        onComplete()
    }
}

// MARK: - View

struct SetupView: View {
    @StateObject private var presenter: SetupPresenter
    @EnvironmentObject private var store: DataStore

    init(store: DataStore, onComplete: @escaping () -> Void) {
        _presenter = StateObject(wrappedValue: SetupPresenter(
            interactor: SetupInteractor(store: store),
            onComplete: onComplete
        ))
    }

    var body: some View {
        ZStack {
            NestColor.ground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: NestSpace.xl) {

                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        PageTitle(title: "Set Up Your House",
                                  subtitle: "Three things, and the app can start checking films against your family instead of against an average one.")
                        WindowBar(fraction: presenter.progress, height: 12)
                    }

                    FieldShell(label: "Your Display Name",
                               hint: "Used on the evening recap. Nothing leaves this device.") {
                        NestTextField(placeholder: "e.g. Mum, Dad, Grandad", text: $presenter.displayName)
                    }

                    FieldShell(label: "Rating Country",
                               hint: "Spain, Britain, the United States and Russia classify differently. The app shows the certificate of the system you choose and never converts one into another.",
                               error: presenter.countryError,
                               required: true) {
                        NestOptionList(options: RatingCountry.allCases,
                                       optionalSelection: $presenter.country,
                                       titleFor: { $0.displayName },
                                       detailFor: { country in
                            country.certifications.map(\.code).joined(separator: " · ")
                        })
                    }

                    setupViewers

                    setupRules

                    FieldShell(label: "Weeknight Bedtime", hint: "Sunday to Thursday.") {
                        NestTimeField(time: $presenter.weeknightBedtime)
                    }

                    FieldShell(label: "Weekend Bedtime", hint: "Friday and Saturday.") {
                        NestTimeField(time: $presenter.weekendBedtime,
                                      presets: [TimeOfDay(hour: 20, minute: 30),
                                                TimeOfDay(hour: 21, minute: 0),
                                                TimeOfDay(hour: 21, minute: 30),
                                                TimeOfDay(hour: 22, minute: 0)])
                    }

                    FieldShell(label: "Screen Time Limit",
                               hint: "Minutes per child, per week. The app shows what is left and never blocks anything. This number is yours.") {
                        NestSlider(value: $presenter.weeklyLimit,
                                   range: 0...1200,
                                   step: 30,
                                   suffix: "min / week",
                                   caption: { minutes in
                            minutes == 0 ? "No limit kept" : "\(TimeFormat.minutes(minutes)) a week"
                        })
                    }

                    PrimaryButton(title: "Save Setup",
                                  busyTitle: "Saving…",
                                  enabled: true,
                                  busy: presenter.isSaving) {
                        presenter.save()
                    }
                    .padding(.top, NestSpace.s)

                    if !presenter.canSave && presenter.attemptedSave {
                        Text("Setup needs a country, a viewer and a rule before it can be saved.")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.stop)
                    }
                }
                .padding(.horizontal, NestSpace.gutter)
                .padding(.top, NestSpace.l)
                .padding(.bottom, NestSpace.huge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $presenter.showViewerForm) {
            ViewerFormView(viewer: presenter.editingViewer,
                           existingCount: presenter.viewers.count,
                           allowDelete: presenter.editingViewer != nil,
                           onSave: { viewer in
                presenter.addViewer(viewer)
                presenter.showViewerForm = false
            }, onDelete: { id in
                presenter.removeViewer(id)
                presenter.showViewerForm = false
            }, onCancel: {
                presenter.showViewerForm = false
            })
        }
        .sheet(isPresented: $presenter.showRuleForm) {
            RuleFormView(rule: presenter.editingRule,
                         viewers: presenter.viewers,
                         country: presenter.country ?? .gb,
                         allowDelete: presenter.editingRule != nil,
                         onSave: { rule in
                presenter.addRule(rule)
                presenter.showRuleForm = false
            }, onDelete: { id in
                presenter.removeRule(id)
                presenter.showRuleForm = false
            }, onCancel: {
                presenter.showRuleForm = false
            })
        }
    }

    // MARK: Sections

    private var setupViewers: some View {
        FieldShell(label: "Household Viewers",
                   hint: "Children, teenagers and adults. Sensitivities can be filled in now or later.",
                   error: presenter.viewerError,
                   required: true) {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                if presenter.viewers.isEmpty {
                    Text("Nobody added yet.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkFaint)
                } else {
                    ForEach(presenter.viewers) { viewer in
                        Button {
                            presenter.editingViewer = viewer
                            presenter.showViewerForm = true
                        } label: {
                            HStack(spacing: NestSpace.m) {
                                ViewerToken(viewer: viewer, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(viewer.name)
                                        .font(NestFont.bodyMedium)
                                        .foregroundColor(NestColor.ink)
                                    Text(viewerSubtitle(viewer))
                                        .font(NestFont.small)
                                        .foregroundColor(NestColor.inkSoft)
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(NestSpace.m)
                            .background(
                                RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                                    .fill(NestColor.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                                    .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Viewer") {
                    presenter.editingViewer = nil
                    presenter.showViewerForm = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func viewerSubtitle(_ viewer: Viewer) -> String {
        var parts = [viewer.role.title]
        if let age = viewer.age { parts.append("\(age)") }
        let sensitivities = viewer.activeSensitivities.count
        if sensitivities > 0 { parts.append("\(sensitivities) sensitivit\(sensitivities == 1 ? "y" : "ies")") }
        return parts.joined(separator: " · ")
    }

    private var setupRules: some View {
        FieldShell(label: "House Rules",
                   hint: "Rules sit above any certificate. You can always allow an exception with a reason.",
                   error: presenter.ruleError,
                   required: true) {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                if presenter.rules.isEmpty {
                    Text("No rules yet.")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkFaint)
                } else {
                    ForEach(presenter.rules) { rule in
                        Button {
                            presenter.editingRule = rule
                            presenter.showRuleForm = true
                        } label: {
                            HStack(alignment: .top, spacing: NestSpace.m) {
                                ReasonSymbolGlyph(symbol: .rule, tint: NestColor.amberSunk, size: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(rule.type.title)
                                        .font(NestFont.bodyMedium)
                                        .foregroundColor(NestColor.ink)
                                        .multilineTextAlignment(.leading)
                                    Text(rule.valueSummary)
                                        .font(NestFont.small)
                                        .foregroundColor(NestColor.inkSoft)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Chevron()
                            }
                            .padding(NestSpace.m)
                            .background(
                                RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                                    .fill(NestColor.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: NestRadius.field, style: .continuous)
                                    .stroke(NestColor.hairline, lineWidth: NestStroke.hair)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Rule") {
                    presenter.editingRule = nil
                    presenter.showRuleForm = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
