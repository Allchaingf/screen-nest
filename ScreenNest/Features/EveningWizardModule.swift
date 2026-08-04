//  EveningWizardModule.swift
//  Screen Nest — Create Evening.
//
//  Five steps with a saved draft. The progress indicator is the same window bar
//  as everywhere else. "Create Evening" blocks itself after the first press, so
//  a second tap can never produce a copy.

import SwiftUI

enum WizardStep: Int, CaseIterable, Identifiable {
    case basics, who, window, title, review
    var id: Int { rawValue }

    var heading: String {
        switch self {
        case .basics: return "Basics"
        case .who: return "Who Is Watching"
        case .window: return "Window"
        case .title: return "Title"
        case .review: return "Review"
        }
    }
}

final class EveningWizardPresenter: ObservableObject {
    @Published var step: WizardStep = .basics
    @Published var name: String = ""
    @Published var date: Date = Date()
    @Published var startTime: TimeOfDay
    @Published var occasion: Occasion = .regular
    @Published var viewerIds: Set<UUID>
    @Published var window: WindowSetup
    @Published var titleId: UUID?
    @Published var episodeRef: EpisodeRef?
    @Published var exceptionReason: String = ""
    @Published var acceptedExceptions: Set<UUID> = []
    @Published var splitPlanned = false

    @Published var attempted = false
    @Published var isCreating = false
    @Published var showTitlePicker = false

    private let store: DataStore
    private let draftId: UUID
    private let planningStartedAt: Date

    init(store: DataStore, prefilledTitleId: UUID?, prefilledViewerIds: [UUID]) {
        self.store = store
        let existingDraft = store.draftEvening
        self.draftId = existingDraft?.id ?? UUID()
        self.planningStartedAt = existingDraft?.planningStartedAt ?? Date()

        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        startTime = existingDraft?.startTime ?? TimeOfDay(hour: now.hour ?? 18, minute: now.minute ?? 30)
        name = existingDraft?.name ?? ""
        date = existingDraft?.date ?? Date()
        occasion = existingDraft?.occasion ?? (Calendar.current.isDateInWeekend(Date()) ? .weekend : .regular)
        let seededViewers = prefilledViewerIds.isEmpty ? (existingDraft?.viewerIds ?? store.viewers.map(\.id)) : prefilledViewerIds
        viewerIds = Set(seededViewers)
        window = existingDraft?.window ?? store.profile.defaultWindow(on: Date())
        titleId = prefilledTitleId ?? existingDraft?.titleId
        episodeRef = existingDraft?.episodeRef
    }

    // MARK: Reads

    var allViewers: [Viewer] { store.viewers }
    var viewers: [Viewer] { store.viewers.filter { viewerIds.contains($0.id) } }
    var titles: [Title] { store.activeTitles.sorted { $0.name < $1.name } }
    var title: Title? { store.title(id: titleId) }
    var country: RatingCountry { store.profile.ratingCountry }

    var effectiveWindow: EveningWindow {
        var setup = window
        let overrides = viewers.compactMap { $0.bedtimeOverride }
        if let earliest = overrides.min(by: { $0.minutesFromMidnight < $1.minutesFromMidnight }),
           earliest.minutesFromMidnight < setup.bedtime.minutesFromMidnight {
            setup.bedtime = earliest
        }
        return WindowEngine.window(setup: setup, referenceTime: startTime)
    }

    var runtime: Int {
        if let episode = episodeRef { return episode.runtimeMinutes }
        return title?.runtimeMinutes ?? 0
    }

    var result: SuitabilityResult? {
        guard let title = title else { return nil }
        let service = SuitabilityService(store: store)
        return service.evaluate(title: title,
                                viewers: viewers,
                                date: date,
                                window: effectiveWindow,
                                runtimeOverride: episodeRef?.runtimeMinutes)
    }

    var brokenRules: [HouseRule] { result?.brokenRules ?? [] }

    var unacceptedRules: [HouseRule] {
        brokenRules.filter { !acceptedExceptions.contains($0.id) }
    }

    // MARK: Validation

    var viewerError: String? {
        attempted && viewerIds.isEmpty ? "Choose at least one viewer." : nil
    }

    var titleError: String? {
        attempted && titleId == nil ? "Choose a title, or save this as a draft for now." : nil
    }

    var exceptionError: String? {
        guard attempted, !unacceptedRules.isEmpty else { return nil }
        return exceptionReason.trimmingCharacters(in: .whitespaces).isEmpty
            ? "This evening breaks a house rule. Write the reason and it will be recorded as a deliberate exception."
            : nil
    }

    func canContinue(from step: WizardStep) -> Bool {
        switch step {
        case .basics: return true
        case .who: return !viewerIds.isEmpty
        case .window: return true
        case .title: return titleId != nil
        case .review: return canCreate
        }
    }

    var canCreate: Bool {
        !viewerIds.isEmpty && titleId != nil &&
        (unacceptedRules.isEmpty || !exceptionReason.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: Intents

    func advance() {
        attempted = true
        guard canContinue(from: step) else {
            NestHaptics.warning()
            return
        }
        attempted = false
        guard let next = WizardStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(NestMotion.base) { step = next }
    }

    func back() {
        guard let previous = WizardStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(NestMotion.base) { step = previous }
    }

    func toggleViewer(_ viewer: Viewer) {
        if viewerIds.contains(viewer.id) { viewerIds.remove(viewer.id) } else { viewerIds.insert(viewer.id) }
        NestHaptics.tap()
    }

    func chooseTitle(_ title: Title) {
        titleId = title.id
        if title.type.isEpisodic, let next = title.nextEpisode {
            episodeRef = EpisodeRef(seasonNumber: next.season,
                                    episodeNumber: next.episode.number,
                                    name: next.episode.name,
                                    runtimeMinutes: next.episode.runtimeMinutes)
        } else {
            episodeRef = nil
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = title.name
        }
        NestHaptics.tap()
    }

    private func buildEvening(state: EveningState) -> Evening {
        var evening = store.evening(id: draftId) ?? Evening(id: draftId)
        evening.name = name.trimmingCharacters(in: .whitespaces)
        evening.date = date
        evening.startTime = startTime
        evening.occasion = occasion
        evening.viewerIds = Array(viewerIds)
        evening.window = window
        evening.titleId = titleId
        evening.episodeRef = episodeRef
        evening.state = state
        evening.planningStartedAt = planningStartedAt
        if let title = title {
            evening.titleSnapshot = TitleSnapshot(title: title, country: country)
        }
        let reason = exceptionReason.trimmingCharacters(in: .whitespaces)
        if !reason.isEmpty {
            evening.exceptions = unacceptedRules.map {
                RuleException(ruleId: $0.id, ruleTitle: $0.type.title, reason: reason)
            }
        }
        if state == .planned {
            evening.createdAt = Date()
        }
        return evening
    }

    func saveDraft(completion: @escaping () -> Void) {
        store.upsertEvening(buildEvening(state: .draft))
        NestHaptics.tap()
        completion()
    }

    func create(completion: @escaping () -> Void) {
        attempted = true
        guard canCreate, !isCreating else {
            NestHaptics.warning()
            return
        }
        isCreating = true
        store.upsertEvening(buildEvening(state: .planned))
        NotificationService.shared.reschedule(for: store.document)
        NestHaptics.success()
        completion()
    }
}

struct EveningWizardView: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter: EveningWizardPresenter

    let onCreated: () -> Void
    let onCancel: () -> Void

    init(prefilledTitleId: UUID? = nil,
         prefilledViewerIds: [UUID] = [],
         onCreated: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        _presenter = StateObject(wrappedValue: EveningWizardPresenter(
            store: .shared,
            prefilledTitleId: prefilledTitleId,
            prefilledViewerIds: prefilledViewerIds))
        self.onCreated = onCreated
        self.onCancel = onCancel
    }

    var body: some View {
        SheetScaffold(title: "Create Evening",
                      subtitle: "Step \(presenter.step.rawValue + 1) of 5 · \(presenter.step.heading)",
                      closeTitle: "Cancel",
                      onClose: onCancel) {

            WindowBar(fraction: Double(presenter.step.rawValue + 1) / 5.0, height: 12)

            Group {
                switch presenter.step {
                case .basics: basics
                case .who: who
                case .window: windowStep
                case .title: titleStep
                case .review: review
                }
            }
            .id(presenter.step)
            .transition(.opacity)

            controls
        }
        .sheet(isPresented: $presenter.showTitlePicker) {
            TitlePickerSheet(titles: presenter.titles) { title in
                presenter.chooseTitle(title)
                presenter.showTitlePicker = false
            } onCancel: {
                presenter.showTitlePicker = false
            }
        }
    }

    // MARK: Steps

    private var basics: some View {
        VStack(alignment: .leading, spacing: NestSpace.l) {
            FieldShell(label: "Evening Name", hint: "Optional — the title is used if you leave it empty.") {
                NestTextField(placeholder: "e.g. Friday film night", text: $presenter.name)
            }
            FieldShell(label: "Date") {
                NestDateStrip(date: $presenter.date)
            }
            FieldShell(label: "Start Time") {
                NestTimeField(time: $presenter.startTime,
                              presets: [TimeOfDay(hour: 17, minute: 30),
                                        TimeOfDay(hour: 18, minute: 0),
                                        TimeOfDay(hour: 18, minute: 30),
                                        TimeOfDay(hour: 19, minute: 0)])
            }
            FieldShell(label: "Occasion") {
                NestOptionList(options: Occasion.allCases,
                               selection: $presenter.occasion,
                               titleFor: { $0.title })
            }
        }
    }

    private var who: some View {
        FieldShell(label: "Who Is Watching",
                   hint: "The check runs against exactly these people.",
                   error: presenter.viewerError,
                   required: true) {
            if presenter.allViewers.isEmpty {
                NestCard {
                    EmptyStateView(title: "No Viewers Yet",
                                   message: "Add someone in the Viewers tab first — an evening has to be for somebody.")
                }
            } else {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    ForEach(presenter.allViewers) { viewer in
                        Button {
                            presenter.toggleViewer(viewer)
                        } label: {
                            HStack(spacing: NestSpace.m) {
                                ViewerToken(viewer: viewer, size: 40,
                                            selected: presenter.viewerIds.contains(viewer.id))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(viewer.name)
                                        .font(NestFont.bodyMedium)
                                        .foregroundColor(NestColor.ink)
                                    Text(detail(viewer))
                                        .font(NestFont.small)
                                        .foregroundColor(NestColor.inkSoft)
                                }
                                Spacer()
                                ZStack {
                                    Circle()
                                        .stroke(presenter.viewerIds.contains(viewer.id) ? NestColor.amber : NestColor.border,
                                                lineWidth: NestStroke.mark)
                                        .frame(width: 20, height: 20)
                                    if presenter.viewerIds.contains(viewer.id) {
                                        Circle().fill(NestColor.amber).frame(width: 10, height: 10)
                                    }
                                }
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
            }
        }
    }

    private func detail(_ viewer: Viewer) -> String {
        var parts = [viewer.role.title]
        if let age = viewer.age { parts.append("\(age)") }
        if let bedtime = viewer.bedtimeOverride { parts.append("bed \(bedtime.display)") }
        return parts.joined(separator: " · ")
    }

    private var windowStep: some View {
        VStack(alignment: .leading, spacing: NestSpace.l) {
            NestPanel(label: "the sum", glow: true) {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    Text("Window = bedtime − now − settling time − expected pauses")
                        .font(NestFont.quote)
                        .foregroundColor(NestColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    WindowGauge(title: "for the film",
                                minutes: presenter.effectiveWindow.filmMinutes,
                                caption: presenter.effectiveWindow.sentence,
                                fraction: Double(presenter.effectiveWindow.filmMinutes)
                                    / Double(max(1, presenter.effectiveWindow.minutesToBedtime)),
                                filmFraction: nil,
                                overflow: presenter.effectiveWindow.filmMinutes == 0)

                    VStack(spacing: NestSpace.xs) {
                        ForEach(presenter.effectiveWindow.breakdown) { line in
                            HStack {
                                Text(line.label)
                                    .font(line.isTotal ? NestFont.bodyMedium : NestFont.small)
                                    .foregroundColor(line.isTotal ? NestColor.ink : NestColor.inkSoft)
                                Spacer()
                                Text("\(line.minutes)")
                                    .font(NestFont.figureMicro)
                                    .foregroundColor(line.isTotal ? NestColor.ink : NestColor.inkFaint)
                            }
                            if !line.isTotal { RowDivider() }
                        }
                    }
                }
            }

            FieldShell(label: "Bedtime") {
                NestTimeField(time: $presenter.window.bedtime)
            }
            FieldShell(label: "Settling Time", hint: "Teeth, story, lights out.") {
                NestSlider(value: $presenter.window.settlingMinutes, range: 0...90, step: 5, suffix: "min")
            }
            FieldShell(label: "Expected Pauses") {
                HStack(spacing: NestSpace.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("how many")
                        NestStepper(value: $presenter.window.pauseCount, range: 0...6, step: 1, suffix: "×")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("each")
                        NestStepper(value: $presenter.window.pauseLengthMinutes, range: 0...30, step: 5, suffix: "min")
                    }
                }
            }
            FieldShell(label: "Snack Break") {
                NestSlider(value: $presenter.window.snackBreakMinutes, range: 0...45, step: 5, suffix: "min")
            }
            FieldShell(label: "Buffer", hint: "The part that always goes missing.") {
                NestSlider(value: $presenter.window.bufferMinutes, range: 0...30, step: 5, suffix: "min")
            }
        }
    }

    private var titleStep: some View {
        VStack(alignment: .leading, spacing: NestSpace.l) {
            FieldShell(label: "Title", error: presenter.titleError, required: true) {
                if let title = presenter.title {
                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        HStack(alignment: .top, spacing: NestSpace.m) {
                            PosterView(title: title, width: 66)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title.name)
                                    .font(NestFont.titleTight)
                                    .foregroundColor(NestColor.ink)
                                Text("\(presenter.runtime) min · window \(presenter.effectiveWindow.filmMinutes) min")
                                    .font(NestFont.small)
                                    .foregroundColor(NestColor.inkSoft)
                                if let episode = presenter.episodeRef {
                                    Text("\(episode.label) — \(episode.name)")
                                        .font(NestFont.small)
                                        .foregroundColor(NestColor.plum)
                                }
                                if let result = presenter.result {
                                    StatusPill(status: result.status, compact: true)
                                }
                            }
                            Spacer()
                        }
                        Button("Choose a different title") { presenter.showTitlePicker = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        Text("Nothing chosen yet.")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkFaint)
                        Button("Choose a Title") { presenter.showTitlePicker = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }

            if let result = presenter.result, let split = result.splitSuggestion {
                FieldShell(label: "Split Over Two Evenings",
                           hint: "Ordinary practice with younger children, not a failed evening.") {
                    NestToggleRow(title: "Plan \(split.first) minutes tonight, \(split.second) next time",
                                  isOn: $presenter.splitPlanned)
                }
            }

            if let result = presenter.result {
                NestCard {
                    VStack(alignment: .leading, spacing: NestSpace.m) {
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
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: NestSpace.l) {
            NestCard(glow: true) {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    SectionLabel("this evening")
                    Text(presenter.name.isEmpty ? (presenter.title?.name ?? "Untitled evening") : presenter.name)
                        .font(NestFont.displaySmall)
                        .foregroundColor(NestColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(TimeFormat.dayFormatter.string(from: presenter.date)) · \(presenter.startTime.display) · \(presenter.occasion.title)")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                    ViewerTokenRow(viewers: presenter.viewers, size: 28)
                    WindowGauge(title: "window",
                                minutes: presenter.effectiveWindow.filmMinutes,
                                caption: "\(presenter.runtime) minutes of film in \(presenter.effectiveWindow.filmMinutes) minutes of window.",
                                fraction: min(1, Double(presenter.runtime) / Double(max(1, presenter.effectiveWindow.filmMinutes))),
                                filmFraction: nil,
                                overflow: presenter.runtime > presenter.effectiveWindow.filmMinutes)
                }
            }

            if let result = presenter.result {
                VStack(alignment: .leading, spacing: NestSpace.m) {
                    SectionHead("What the Check Says")
                    NestCard {
                        VStack(alignment: .leading, spacing: NestSpace.l) {
                            HStack {
                                StatusPill(status: result.status)
                                Spacer()
                            }
                            ForEach(result.reasons.filter { $0.tone == .blocking || $0.tone == .caution }) { reason in
                                ReasonRow(reason: reason)
                            }
                            if result.reasons.allSatisfy({ $0.tone != .blocking && $0.tone != .caution }) {
                                Text("Nothing is standing in the way of this one.")
                                    .font(NestFont.body)
                                    .foregroundColor(NestColor.go)
                            }
                        }
                    }
                }
            }

            if !presenter.unacceptedRules.isEmpty {
                FieldShell(label: "Allow Exception",
                           hint: "The app does not forbid anything. It records that you chose to.",
                           error: presenter.exceptionError,
                           required: true) {
                    VStack(alignment: .leading, spacing: NestSpace.m) {
                        ForEach(presenter.unacceptedRules) { rule in
                            HStack(spacing: NestSpace.s) {
                                ReasonSymbolGlyph(symbol: .rule, tint: NestColor.stop, size: 16)
                                Text(rule.type.title)
                                    .font(NestFont.smallMedium)
                                    .foregroundColor(NestColor.stop)
                                Spacer()
                            }
                        }
                        NestTextField(placeholder: "e.g. parent watching together",
                                      text: $presenter.exceptionReason,
                                      invalid: presenter.exceptionError != nil)
                        if !presenter.exceptionReason.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Rule broken on purpose: \(presenter.exceptionReason).")
                                .font(NestFont.quote)
                                .foregroundColor(NestColor.plum)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: NestSpace.m) {
            MinuteTicks(count: 40, height: 5, emphasisEvery: 5, colour: NestColor.hairline)

            if presenter.step == .review {
                PrimaryButton(title: "Create Evening",
                              busyTitle: "Creating…",
                              busy: presenter.isCreating) {
                    presenter.create(completion: onCreated)
                }
            } else {
                PrimaryButton(title: "Continue") { presenter.advance() }
            }

            HStack(spacing: NestSpace.m) {
                if presenter.step != .basics {
                    Button("Back") { presenter.back() }
                        .buttonStyle(QuietButtonStyle())
                }
                Spacer()
                Button("Save as Draft") {
                    presenter.saveDraft(completion: onCancel)
                }
                .buttonStyle(QuietButtonStyle(tint: NestColor.amberSunk))
            }
        }
        .padding(.top, NestSpace.s)
    }
}
