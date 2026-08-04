//  ViewerFormModule.swift
//  Screen Nest — add / edit a viewer.
//
//  The sensitivities list is the reason this app exists, so it is explained on
//  the screen rather than buried in a help page.

import SwiftUI

final class ViewerFormPresenter: ObservableObject {

    @Published var name: String
    @Published var role: ViewerRole
    @Published var age: Int?
    @Published var colourIndex: Int
    @Published var attentionSpan: Int
    @Published var selectedAspects: Set<ContentAspect>
    @Published var loves: [String]
    @Published var avoids: [String]
    @Published var lovesDraft: String = ""
    @Published var avoidsDraft: String = ""
    @Published var hasBedtimeOverride: Bool
    @Published var bedtimeOverride: TimeOfDay
    @Published var notes: String
    @Published var hasWeeklyLimit: Bool
    @Published var weeklyLimit: Int
    @Published var rolloverAllowed: Bool

    @Published var attemptedSave = false
    @Published var isSaving = false
    @Published var confirmingDelete = false

    private let original: Viewer?
    private let existingCount: Int

    init(viewer: Viewer?, existingCount: Int) {
        self.original = viewer
        self.existingCount = existingCount
        name = viewer?.name ?? ""
        role = viewer?.role ?? .child
        age = viewer?.age
        colourIndex = viewer?.colourIndex ?? (existingCount % NestColor.viewerHues.count)
        attentionSpan = viewer?.attentionSpanMinutes ?? 60
        selectedAspects = Set((viewer?.activeSensitivities ?? []).map(\.aspect))
        loves = viewer?.loves ?? []
        avoids = viewer?.avoids ?? []
        hasBedtimeOverride = viewer?.bedtimeOverride != nil
        bedtimeOverride = viewer?.bedtimeOverride ?? TimeOfDay(hour: 20, minute: 0)
        notes = viewer?.notes ?? ""
        hasWeeklyLimit = viewer?.weeklyLimitMinutes != nil
        weeklyLimit = viewer?.weeklyLimitMinutes ?? 420
        rolloverAllowed = viewer?.rolloverAllowed ?? false
    }

    var isEditing: Bool { original != nil }
    var title: String { isEditing ? "Edit Viewer" : "Add Viewer" }

    var retired: [SensitivityRecord] { original?.retiredSensitivities ?? [] }

    // MARK: Validation

    var nameError: String? {
        guard attemptedSave else { return nil }
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a name to continue." : nil
    }

    var ageError: String? {
        guard attemptedSave, role.requiresAge else { return nil }
        guard let age = age else { return "Age is required for a child — the check depends on it." }
        return (age < 0 || age > 25) ? "Enter an age between 0 and 25." : nil
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (!role.requiresAge || (age.map { $0 >= 0 && $0 <= 25 } ?? false))
    }

    // MARK: Intents

    func toggle(_ aspect: ContentAspect) {
        if selectedAspects.contains(aspect) {
            selectedAspects.remove(aspect)
        } else {
            selectedAspects.insert(aspect)
        }
        NestHaptics.tap()
    }

    func addLove() {
        let trimmed = lovesDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !loves.contains(trimmed) else { return }
        loves.append(trimmed)
        lovesDraft = ""
        NestHaptics.tap()
    }

    func addAvoid() {
        let trimmed = avoidsDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !avoids.contains(trimmed) else { return }
        avoids.append(trimmed)
        avoidsDraft = ""
        NestHaptics.tap()
    }

    /// Builds the viewer, preserving sensitivity dates that already existed and
    /// keeping every retired record in the history.
    func build() -> Viewer {
        var viewer = original ?? Viewer(name: "")
        viewer.name = name.trimmingCharacters(in: .whitespaces)
        viewer.role = role
        viewer.age = role.requiresAge || role == .teenager ? age : age
        viewer.colourIndex = colourIndex
        viewer.attentionSpanMinutes = attentionSpan
        viewer.loves = loves
        viewer.avoids = avoids
        viewer.bedtimeOverride = hasBedtimeOverride ? bedtimeOverride : nil
        viewer.notes = notes
        viewer.weeklyLimitMinutes = hasWeeklyLimit ? weeklyLimit : nil
        viewer.rolloverAllowed = rolloverAllowed

        var records = viewer.sensitivities
        // Anything unticked that was active becomes grown-out-of, keeping its history.
        for index in records.indices where records[index].isActive && !selectedAspects.contains(records[index].aspect) {
            records[index].grownOutOn = Date()
        }
        // Anything ticked that is not currently active is added or revived.
        for aspect in selectedAspects {
            if let index = records.firstIndex(where: { $0.aspect == aspect && $0.isActive }) {
                _ = index
                continue
            }
            if let index = records.lastIndex(where: { $0.aspect == aspect }) {
                records[index].grownOutOn = nil
            } else {
                records.append(SensitivityRecord(aspect: aspect))
            }
        }
        viewer.sensitivities = records
        return viewer
    }
}

struct ViewerFormView: View {
    @StateObject private var presenter: ViewerFormPresenter

    let allowDelete: Bool
    let onSave: (Viewer) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    private let viewerId: UUID?

    init(viewer: Viewer?,
         existingCount: Int,
         allowDelete: Bool,
         onSave: @escaping (Viewer) -> Void,
         onDelete: @escaping (UUID) -> Void,
         onCancel: @escaping () -> Void) {
        _presenter = StateObject(wrappedValue: ViewerFormPresenter(viewer: viewer, existingCount: existingCount))
        self.allowDelete = allowDelete
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.viewerId = viewer?.id
    }

    var body: some View {
        SheetScaffold(title: presenter.title,
                      subtitle: "Name and, for a child, age are required.",
                      closeTitle: "Cancel",
                      onClose: onCancel) {

            FieldShell(label: "Name", error: presenter.nameError, required: true) {
                NestTextField(placeholder: "Name", text: $presenter.name, invalid: presenter.nameError != nil)
            }

            FieldShell(label: "Role") {
                NestSegmented(options: ViewerRole.allCases,
                              selection: $presenter.role,
                              titleFor: { $0.title })
            }

            FieldShell(label: "Age",
                       hint: presenter.role.requiresAge
                        ? "Certificates are compared against this."
                        : "Optional for teenagers and adults.",
                       error: presenter.ageError,
                       required: presenter.role.requiresAge) {
                NestNumberField(placeholder: "Age",
                                value: $presenter.age,
                                suffix: "years old",
                                invalid: presenter.ageError != nil)
            }

            FieldShell(label: "Colour", hint: "Used for this viewer's token throughout the app.") {
                HStack(spacing: NestSpace.m) {
                    ForEach(0..<NestColor.viewerHues.count, id: \.self) { index in
                        Button {
                            NestHaptics.tap()
                            withAnimation(NestMotion.snap) { presenter.colourIndex = index }
                        } label: {
                            ZStack {
                                Circle().fill(NestColor.viewerHue(index).opacity(0.25))
                                Circle().stroke(NestColor.viewerHue(index),
                                                lineWidth: presenter.colourIndex == index ? 3 : 1)
                            }
                            .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            FieldShell(label: "Attention Span",
                       hint: "How long this viewer manages without a pause. A longer film is offered as two evenings instead of being refused.") {
                NestSlider(value: $presenter.attentionSpan,
                           range: 10...180,
                           step: 5,
                           suffix: "min at a time",
                           caption: { minutes in
                    minutes < 45 ? "Short sittings" : (minutes < 95 ? "A normal film is a stretch" : "Sits through a feature")
                })
            }

            sensitivities

            FieldShell(label: "Loves",
                       hint: "Dinosaurs, space, musical numbers, animal friendships. Used when picking.") {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    HStack(spacing: NestSpace.s) {
                        NestTextField(placeholder: "Add something they love", text: $presenter.lovesDraft)
                        Button("Add") { presenter.addLove() }
                            .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                    }
                    if !presenter.loves.isEmpty {
                        ChipFlow(items: presenter.loves) { item in
                            NestChip(title: item, selected: true, tint: NestColor.go) {
                                presenter.loves.removeAll { $0 == item }
                            }
                        }
                    }
                }
            }

            FieldShell(label: "Avoids", hint: "Things to steer around that are not on the sensitivity list.") {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    HStack(spacing: NestSpace.s) {
                        NestTextField(placeholder: "Add something to avoid", text: $presenter.avoidsDraft)
                        Button("Add") { presenter.addAvoid() }
                            .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
                    }
                    if !presenter.avoids.isEmpty {
                        ChipFlow(items: presenter.avoids) { item in
                            NestChip(title: item, selected: true, tint: NestColor.stop) {
                                presenter.avoids.removeAll { $0 == item }
                            }
                        }
                    }
                }
            }

            FieldShell(label: "Bedtime Override", hint: "Only if this viewer goes to bed at a different time from the house.") {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    NestToggleRow(title: "Different bedtime", isOn: $presenter.hasBedtimeOverride)
                    if presenter.hasBedtimeOverride {
                        NestTimeField(time: $presenter.bedtimeOverride)
                    }
                }
            }

            FieldShell(label: "Weekly Screen Time", hint: "The remainder is shown, never enforced.") {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    NestToggleRow(title: "Keep a weekly limit for this viewer", isOn: $presenter.hasWeeklyLimit)
                    if presenter.hasWeeklyLimit {
                        NestSlider(value: $presenter.weeklyLimit, range: 0...1200, step: 30, suffix: "min / week")
                        NestToggleRow(title: "Rollover Allowed",
                                      subtitle: "Unused minutes carry into the next week.",
                                      isOn: $presenter.rolloverAllowed)
                    }
                }
            }

            FieldShell(label: "Notes") {
                NestTextArea(placeholder: "Anything worth remembering.", text: $presenter.notes)
            }

            VStack(spacing: NestSpace.m) {
                PrimaryButton(title: presenter.isEditing ? "Save Viewer" : "Add Viewer",
                              busy: presenter.isSaving) {
                    presenter.attemptedSave = true
                    guard presenter.isValid else {
                        NestHaptics.warning()
                        return
                    }
                    presenter.isSaving = true
                    onSave(presenter.build())
                }

                if allowDelete, let id = viewerId {
                    Button("Remove Viewer") {
                        NestHaptics.tap()
                        presenter.confirmingDelete = true
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: NestColor.stop))
                    .alert("Remove this viewer?", isPresented: $presenter.confirmingDelete) {
                        Button("Cancel", role: .cancel) {}
                        Button("Remove", role: .destructive) { onDelete(id) }
                    } message: {
                        Text("Finished evenings keep their record. Planned evenings lose this viewer.")
                    }
                }
            }
            .padding(.top, NestSpace.s)
        }
    }

    private var sensitivities: some View {
        FieldShell(label: "Sensitivities") {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                HStack(alignment: .top, spacing: NestSpace.s) {
                    Rectangle().fill(NestColor.amber).frame(width: 2)
                    Text("A rating says “10+”. It does not know that this child cannot watch an animal get hurt.")
                        .font(NestFont.quote)
                        .foregroundColor(NestColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ChipFlow(items: ContentAspect.sensitivityOptions) { aspect in
                    NestChip(title: aspect.title,
                             selected: presenter.selectedAspects.contains(aspect),
                             tint: NestColor.stop,
                             glyph: aspect) {
                        presenter.toggle(aspect)
                    }
                }

                if !presenter.retired.isEmpty {
                    VStack(alignment: .leading, spacing: NestSpace.s) {
                        SectionLabel("grown out of")
                        ForEach(presenter.retired) { record in
                            HStack(spacing: NestSpace.s) {
                                AspectGlyph(aspect: record.aspect, size: 18, tint: NestColor.inkSoft)
                                Text(record.aspect.title)
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkSoft)
                                Spacer()
                                if let date = record.grownOutOn {
                                    Text(TimeFormat.shortDayFormatter.string(from: date))
                                        .font(NestFont.figureMicro)
                                        .foregroundColor(NestColor.inkFaint)
                                }
                            }
                        }
                        Text("Ticking one again brings it back from today.")
                            .font(NestFont.micro)
                            .foregroundColor(NestColor.inkFaint)
                    }
                    .padding(.top, NestSpace.xs)
                }
            }
        }
    }
}
