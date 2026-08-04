//  RuleFormModule.swift
//  Screen Nest — add / edit a house rule.

import SwiftUI

final class RuleFormPresenter: ObservableObject {

    @Published var type: RuleType
    @Published var age: Int?
    @Published var certificationCode: String
    @Published var minutes: Int
    @Published var time: TimeOfDay
    @Published var appliesToEveryone: Bool
    @Published var appliesTo: Set<UUID>
    @Published var exceptionAllowed: Bool
    @Published var notes: String

    @Published var attemptedSave = false
    @Published var isSaving = false
    @Published var confirmingDelete = false

    let country: RatingCountry
    let viewers: [Viewer]
    private let original: HouseRule?

    init(rule: HouseRule?, viewers: [Viewer], country: RatingCountry) {
        self.original = rule
        self.viewers = viewers
        self.country = country
        type = rule?.type ?? .noHorror
        age = rule?.age
        certificationCode = rule?.certificationCode ?? country.certifications.first?.code ?? ""
        minutes = rule?.minutes ?? 90
        time = rule?.time ?? TimeOfDay(hour: 20, minute: 30)
        appliesToEveryone = (rule?.appliesTo.isEmpty ?? true)
        appliesTo = Set(rule?.appliesTo ?? [])
        exceptionAllowed = rule?.exceptionAllowed ?? true
        notes = rule?.notes ?? ""
    }

    var isEditing: Bool { original != nil }
    var title: String { isEditing ? "Edit Rule" : "Add Rule" }

    var ageError: String? {
        guard attemptedSave, type.needsAge else { return nil }
        guard let age = age, age > 0, age <= 21 else { return "Enter the age this rule applies below." }
        return nil
    }

    var appliesError: String? {
        guard attemptedSave, !appliesToEveryone, appliesTo.isEmpty else { return nil }
        return "Choose who this applies to, or set it for everyone."
    }

    var isValid: Bool {
        if type.needsAge, !(age.map { $0 > 0 && $0 <= 21 } ?? false) { return false }
        if !appliesToEveryone && appliesTo.isEmpty { return false }
        return true
    }

    func build() -> HouseRule {
        var rule = original ?? HouseRule(type: type)
        rule.type = type
        rule.age = type.needsAge ? age : nil
        rule.certificationCode = type.needsCertification ? certificationCode : nil
        rule.minutes = type.needsMinutes ? minutes : nil
        rule.time = type.needsTime ? time : nil
        rule.appliesTo = appliesToEveryone ? [] : Array(appliesTo)
        rule.exceptionAllowed = exceptionAllowed
        rule.notes = notes
        rule.isActive = true
        return rule
    }

    var changeNote: String {
        isEditing ? "Edited — \(build().valueSummary)" : "Added — \(build().valueSummary)"
    }
}

struct RuleFormView: View {
    @StateObject private var presenter: RuleFormPresenter

    let allowDelete: Bool
    let onSave: (HouseRule) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    private let ruleId: UUID?

    init(rule: HouseRule?,
         viewers: [Viewer],
         country: RatingCountry,
         allowDelete: Bool,
         onSave: @escaping (HouseRule) -> Void,
         onDelete: @escaping (UUID) -> Void,
         onCancel: @escaping () -> Void) {
        _presenter = StateObject(wrappedValue: RuleFormPresenter(rule: rule, viewers: viewers, country: country))
        self.allowDelete = allowDelete
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.ruleId = rule?.id
    }

    var body: some View {
        SheetScaffold(title: presenter.title,
                      subtitle: "Rules sit above any certificate.",
                      closeTitle: "Cancel",
                      onClose: onCancel) {

            FieldShell(label: "Rule Type", required: true) {
                NestOptionList(options: RuleType.allCases,
                               selection: $presenter.type,
                               titleFor: { $0.title },
                               detailFor: { $0.explanation })
            }

            if presenter.type.needsAge {
                FieldShell(label: "Applies Below Age",
                           error: presenter.ageError,
                           required: true) {
                    NestNumberField(placeholder: "Age",
                                    value: $presenter.age,
                                    suffix: "years old",
                                    invalid: presenter.ageError != nil)
                }
            }

            if presenter.type.needsCertification {
                FieldShell(label: "Highest Certificate Allowed",
                           hint: "In \(presenter.country.displayName).") {
                    ChipFlow(items: presenter.country.certifications.map(\.code)) { code in
                        NestChip(title: code,
                                 selected: presenter.certificationCode == code) {
                            presenter.certificationCode = code
                        }
                    }
                }
            }

            if presenter.type.needsMinutes {
                FieldShell(label: "Maximum Runtime") {
                    NestSlider(value: $presenter.minutes, range: 15...240, step: 5, suffix: "min")
                }
            }

            if presenter.type.needsTime {
                FieldShell(label: "Cut-off Time") {
                    NestTimeField(time: $presenter.time)
                }
            }

            FieldShell(label: "Applies To", error: presenter.appliesError) {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    NestToggleRow(title: "Everyone in the house", isOn: $presenter.appliesToEveryone)
                    if !presenter.appliesToEveryone {
                        if presenter.viewers.isEmpty {
                            Text("No viewers yet — this rule will apply to everyone.")
                                .font(NestFont.small)
                                .foregroundColor(NestColor.inkFaint)
                        } else {
                            ChipFlow(items: presenter.viewers) { viewer in
                                NestChip(title: viewer.name,
                                         selected: presenter.appliesTo.contains(viewer.id),
                                         tint: NestColor.viewerHue(viewer.colourIndex)) {
                                    if presenter.appliesTo.contains(viewer.id) {
                                        presenter.appliesTo.remove(viewer.id)
                                    } else {
                                        presenter.appliesTo.insert(viewer.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            FieldShell(label: "Exception Allowed",
                       hint: "With this on, an evening can break the rule on purpose — the reason is written into the record.") {
                NestToggleRow(title: "Allow a deliberate exception",
                              subtitle: "Rule broken on purpose: parent watching together.",
                              isOn: $presenter.exceptionAllowed)
            }

            FieldShell(label: "Notes") {
                NestTextArea(placeholder: "Why this rule exists.", text: $presenter.notes, minHeight: 70)
            }

            VStack(spacing: NestSpace.m) {
                PrimaryButton(title: presenter.isEditing ? "Save Rule" : "Add Rule",
                              busy: presenter.isSaving) {
                    presenter.attemptedSave = true
                    guard presenter.isValid else {
                        NestHaptics.warning()
                        return
                    }
                    presenter.isSaving = true
                    onSave(presenter.build())
                }

                if allowDelete, let id = ruleId {
                    Button("Remove Rule") {
                        NestHaptics.tap()
                        presenter.confirmingDelete = true
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: NestColor.stop))
                    .alert("Remove this rule?", isPresented: $presenter.confirmingDelete) {
                        Button("Cancel", role: .cancel) {}
                        Button("Remove", role: .destructive) { onDelete(id) }
                    } message: {
                        Text("The rule history keeps a record that it existed.")
                    }
                }
            }
            .padding(.top, NestSpace.s)
        }
    }
}
