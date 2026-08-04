//  SuitabilityModule.swift
//  Screen Nest — the suitability check.
//
//  The most important screen in the app, and the one with no score on it.
//  Every line is a sentence a parent could have said out loud, and the status
//  at the top is only a summary of those lines.

import SwiftUI

final class SuitabilityPresenter: ObservableObject {
    @Published var selectedViewerIds: Set<UUID>
    @Published private(set) var result: SuitabilityResult?
    @Published var date: Date = Date()
    @Published var showWizard = false
    @Published var toast: NestToast?

    let titleId: UUID
    private let store: DataStore

    init(titleId: UUID, store: DataStore, preselected: [UUID]? = nil) {
        self.titleId = titleId
        self.store = store
        self.selectedViewerIds = Set(preselected ?? store.viewers.map(\.id))
        refresh()
    }

    var title: Title? { store.title(id: titleId) }
    var allViewers: [Viewer] { store.viewers }
    var viewers: [Viewer] { store.viewers.filter { selectedViewerIds.contains($0.id) } }
    var country: RatingCountry { store.profile.ratingCountry }
    var window: EveningWindow { SuitabilityService(store: store).window(for: viewers, on: date) }
    var warningNotes: [ContentNote] { store.warningNotes(for: titleId) }

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
        guard let title = title else {
            result = nil
            return
        }
        let service = SuitabilityService(store: store)
        let runtime = title.type.isEpisodic ? (title.nextEpisode?.episode.runtimeMinutes ?? title.runtimeMinutes) : nil
        result = service.evaluate(title: title, viewers: viewers, date: date, runtimeOverride: runtime)
    }

    func show(_ toast: NestToast) {
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }
}

struct SuitabilityView: View {
    let titleId: UUID
    var preselectedViewers: [UUID]? = nil

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter: SuitabilityPresenter

    init(titleId: UUID, preselectedViewers: [UUID]? = nil) {
        self.titleId = titleId
        self.preselectedViewers = preselectedViewers
        _presenter = StateObject(wrappedValue: SuitabilityPresenter(titleId: titleId,
                                                                    store: .shared,
                                                                    preselected: preselectedViewers))
    }

    var body: some View {
        ZStack {
            NestScreen(bottomInset: NestSpace.huge) {
                if let title = presenter.title, let result = presenter.result {
                    heading(title: title, result: result)
                    viewerPicker
                    windowSection(result: result)
                    if let changes = result.changesWhen {
                        changesCard(changes, status: result.status)
                    }
                    warningsSection
                    reasonsSection(result: result)
                    perViewerSection(result: result)
                    actions(title: title, result: result)
                } else {
                    ErrorStateView(title: "This title is no longer in the library",
                                   message: "It may have been deleted. Finished evenings keep their own record of it.")
                }
            }
            ToastOverlay(toast: presenter.toast)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { presenter.refresh() }
        .onReceive(store.$document.dropFirst()) { _ in presenter.refresh() }
        .sheet(isPresented: $presenter.showWizard) {
            EveningWizardView(prefilledTitleId: presenter.titleId,
                              prefilledViewerIds: Array(presenter.selectedViewerIds)) {
                presenter.showWizard = false
                presenter.show(NestToast(message: "Evening created"))
            } onCancel: {
                presenter.showWizard = false
            }
        }
    }

    // MARK: Sections

    private func heading(title: Title, result: SuitabilityResult) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.l) {
            HStack(alignment: .top, spacing: NestSpace.l) {
                PosterView(title: title, width: 92)
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    Text(title.name)
                        .font(NestFont.displaySmall)
                        .foregroundColor(NestColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(title))
                        .font(NestFont.small)
                        .foregroundColor(NestColor.inkSoft)
                    StatusPill(status: result.status)
                }
                Spacer(minLength: 0)
            }

            if !title.contentAspects.isEmpty {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    SectionLabel("what is in it")
                    ChipFlow(items: title.contentAspects) { aspect in
                        NestChip(title: aspect.title,
                                 selected: presenter.viewers.contains { $0.activeAspects.contains(aspect) },
                                 tint: NestColor.stop,
                                 glyph: aspect)
                    }
                }
            }
        }
    }

    private func subtitle(_ title: Title) -> String {
        var parts = [title.type.title, "\(title.runtimeMinutes) min"]
        if let year = title.releaseYear { parts.append("\(year)") }
        if let cert = title.certification(for: presenter.country) {
            parts.append("\(cert) · \(presenter.country.bodyName)")
        } else {
            parts.append("no certificate for \(presenter.country.countryName)")
        }
        return parts.joined(separator: " · ")
    }

    private var viewerPicker: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Who Is Watching",
                        subtitle: "The check changes with the room. Tap a token to include or leave someone out.")
            if presenter.allViewers.isEmpty {
                NestCard {
                    EmptyStateView(title: "No Viewers Yet",
                                   message: "The check has to be about someone in particular.",
                                   primaryTitle: "Add Viewer",
                                   primaryAction: { router.openViewerAdd() })
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NestSpace.l) {
                        ForEach(presenter.allViewers) { viewer in
                            Button {
                                presenter.toggle(viewer)
                            } label: {
                                ViewerToken(viewer: viewer,
                                            size: 46,
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
    }

    private func windowSection(result: SuitabilityResult) -> some View {
        NestPanel(label: "tonight’s window") {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                WindowGauge(title: "for the film",
                            minutes: result.windowMinutes,
                            caption: presenter.window.sentence,
                            fraction: min(1, Double(result.runtimeMinutes) / Double(max(1, result.windowMinutes))),
                            filmFraction: nil,
                            overflow: !result.fitsWindow && result.runtimeMinutes > 0)

                VStack(spacing: NestSpace.xs) {
                    ForEach(presenter.window.breakdown) { line in
                        HStack {
                            Text(line.label)
                                .font(line.isTotal ? NestFont.bodyMedium : NestFont.small)
                                .foregroundColor(line.isTotal ? NestColor.ink : NestColor.inkSoft)
                            Spacer()
                            Text(line.isTotal ? "\(line.minutes)" : (line.minutes < 0 ? "\(line.minutes)" : "+\(line.minutes)"))
                                .font(NestFont.figureMicro)
                                .foregroundColor(line.isTotal ? NestColor.ink : NestColor.inkFaint)
                        }
                        if line.isTotal == false {
                            RowDivider()
                        }
                    }
                }
                .padding(.top, NestSpace.xs)
            }
        }
    }

    private func changesCard(_ text: String, status: SuitabilityStatus) -> some View {
        NestCard(tint: status == .fitsEveryone ? NestColor.goWash : NestColor.amberWash,
                 stroke: (status == .fitsEveryone ? NestColor.go : NestColor.amber).opacity(0.4)) {
            VStack(alignment: .leading, spacing: NestSpace.s) {
                SectionLabel("when this changes", colour: NestColor.amberSunk)
                Text(text)
                    .font(NestFont.quote)
                    .foregroundColor(NestColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if !presenter.warningNotes.isEmpty {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                SectionHead("Warn Before Watching",
                            subtitle: "Recorded in this house, about these children.")
                ForEach(presenter.warningNotes) { note in
                    NestCard(tint: NestColor.stopWash, stroke: NestColor.stop.opacity(0.35)) {
                        VStack(alignment: .leading, spacing: NestSpace.xs) {
                            HStack {
                                if let timecode = note.timecode {
                                    Text("At \(timecode)")
                                        .font(NestFont.figureMicro)
                                        .foregroundColor(NestColor.stop)
                                }
                                Spacer()
                                nestTracked(note.severity.title.lowercased(), kern: 0.7)
                                    .font(NestFont.label)
                                    .foregroundColor(NestColor.stop)
                            }
                            Text(note.whatHappens)
                                .font(NestFont.body)
                                .foregroundColor(NestColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if !note.adviceNextTime.isEmpty {
                                Text(note.adviceNextTime)
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

    private func reasonsSection(result: SuitabilityResult) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("The Check", subtitle: "No score. Just what is true tonight.")
            NestCard {
                VStack(alignment: .leading, spacing: NestSpace.l) {
                    ForEach(Array(result.reasons.enumerated()), id: \.element.id) { index, reason in
                        ReasonRow(reason: reason)
                            .nestRise(index)
                    }
                }
            }
        }
    }

    private func perViewerSection(result: SuitabilityResult) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            if !result.viewerVerdicts.isEmpty {
                SectionHead("For Each of Them")
                ForEach(result.viewerVerdicts) { verdict in
                    NestCard {
                        VStack(alignment: .leading, spacing: NestSpace.m) {
                            HStack(spacing: NestSpace.m) {
                                ViewerToken(viewer: verdict.viewer, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verdict.viewer.name)
                                        .font(NestFont.titleTight)
                                        .foregroundColor(NestColor.ink)
                                    Text(verdictSummary(verdict))
                                        .font(NestFont.small)
                                        .foregroundColor(verdict.blockedByAgeOrContent ? NestColor.stop : NestColor.inkSoft)
                                }
                                Spacer()
                            }
                            VStack(alignment: .leading, spacing: NestSpace.m) {
                                ForEach(verdict.reasons) { reason in
                                    ReasonRow(reason: reason)
                                }
                            }
                            if let changes = verdict.changesWhen {
                                Text(changes)
                                    .font(NestFont.quote)
                                    .foregroundColor(NestColor.amberSunk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func verdictSummary(_ verdict: ViewerVerdict) -> String {
        if verdict.blockedByAgeOrContent { return "Held back for now" }
        if verdict.needsAdult { return "Fine with an adult in the room" }
        return "Nothing marked against them"
    }

    private func actions(title: Title, result: SuitabilityResult) -> some View {
        VStack(spacing: NestSpace.m) {
            MinuteTicks(count: 40, height: 5, emphasisEvery: 5, colour: NestColor.hairline)

            PrimaryButton(title: "Add to an Evening") {
                presenter.showWizard = true
            }

            if let split = result.splitSuggestion {
                Button("Split Over Two Evenings — \(split.first) + \(split.second) min") {
                    NestHaptics.tap()
                    presenter.showWizard = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            NavigationLink(destination: TitleDetailView(titleId: title.id)) {
                Text("Open the Title")
                    .font(NestFont.heading)
                    .foregroundColor(NestColor.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
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

            Text("The app advises. You decide — you can choose anything in the library for any evening.")
                .font(NestFont.micro)
                .foregroundColor(NestColor.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, NestSpace.xs)
        }
        .padding(.top, NestSpace.s)
    }
}
