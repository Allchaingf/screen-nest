//  AfterWatchModule.swift
//  Screen Nest — what actually happened.
//
//  Opens straight after the evening ends, because by tomorrow the detail is
//  gone. One impression is required, for at least one viewer — an entirely
//  empty reaction is worse than none, because it looks like data.

import SwiftUI

final class AfterWatchPresenter: ObservableObject {
    @Published var reactions: [UUID: Reaction] = [:]
    @Published var parentNote: String = ""
    @Published var outcome: EveningOutcome
    @Published var attempted = false
    @Published var isSaving = false
    @Published var celebrate = false

    private let store: DataStore
    let eveningId: UUID

    init(eveningId: UUID, store: DataStore) {
        self.eveningId = eveningId
        self.store = store
        let evening = store.evening(id: eveningId)
        self.outcome = evening?.outcome ?? .finished
        self.parentNote = evening?.parentNote ?? ""
        var map: [UUID: Reaction] = [:]
        for id in evening?.viewerIds ?? [] {
            map[id] = evening?.reactions.first { $0.viewerId == id } ?? Reaction(viewerId: id)
        }
        self.reactions = map
    }

    var evening: Evening? { store.evening(id: eveningId) }
    var viewers: [Viewer] { store.viewers(ids: evening?.viewerIds ?? []) }
    var title: Title? { store.title(id: evening?.titleId) }
    var marks: [MarkedMoment] { evening?.watch.marks ?? [] }

    var watchedMinutes: Int {
        guard let evening = evening else { return 0 }
        return ScreenTimeEngine.watchedMinutes(evening)
    }

    var impressionError: String? {
        guard attempted else { return nil }
        return reactions.values.contains { $0.impression != nil }
            ? nil
            : "Record an overall impression for at least one viewer."
    }

    var isValid: Bool {
        reactions.values.contains { $0.impression != nil }
    }

    func binding(for viewerId: UUID) -> Binding<Reaction> {
        Binding(
            get: { self.reactions[viewerId] ?? Reaction(viewerId: viewerId) },
            set: { self.reactions[viewerId] = $0 }
        )
    }

    func save(completion: @escaping () -> Void) {
        attempted = true
        guard isValid, !isSaving else {
            NestHaptics.warning()
            return
        }
        isSaving = true
        guard var evening = evening else { return }
        evening.reactions = Array(reactions.values).filter { !$0.isEmpty }
        evening.parentNote = parentNote.trimmingCharacters(in: .whitespaces)
        evening.outcome = outcome
        evening.state = .completed
        evening.completedAt = evening.completedAt ?? Date()
        store.upsertEvening(evening)
        NotificationService.shared.reschedule(for: store.document)

        // The one celebration in this app: an evening that is genuinely closed.
        celebrate = true
        NestHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            completion()
        }
    }
}

struct AfterWatchView: View {
    let eveningId: UUID
    let onClose: () -> Void

    @EnvironmentObject private var store: DataStore
    @StateObject private var presenter: AfterWatchPresenter

    init(eveningId: UUID, onClose: @escaping () -> Void) {
        self.eveningId = eveningId
        self.onClose = onClose
        _presenter = StateObject(wrappedValue: AfterWatchPresenter(eveningId: eveningId, store: .shared))
    }

    var body: some View {
        ZStack {
            SheetScaffold(title: "What Actually Happened",
                          subtitle: presenter.title?.name ?? presenter.evening?.displayName,
                          closeTitle: "Later",
                          onClose: onClose) {

                summary

                if presenter.viewers.isEmpty {
                    NestCard {
                        EmptyStateView(title: "No Viewers on This Evening",
                                       message: "Nothing to record against. You can still add a parent note below.")
                    }
                } else {
                    if let error = presenter.impressionError {
                        HStack(alignment: .top, spacing: 6) {
                            ReasonSymbolGlyph(symbol: .unknown, tint: NestColor.stop, size: 14)
                            Text(error)
                                .font(NestFont.small)
                                .foregroundColor(NestColor.stop)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(presenter.viewers) { viewer in
                        ReactionCard(viewer: viewer, reaction: presenter.binding(for: viewer.id))
                    }
                }

                FieldShell(label: "Outcome") {
                    NestOptionList(options: EveningOutcome.allCases,
                                   selection: $presenter.outcome,
                                   titleFor: { $0.title })
                }

                FieldShell(label: "Parent Note",
                           hint: "The scene that raised questions, what you had to talk about, what to explain in advance next time.") {
                    NestTextArea(placeholder: "Parent note", text: $presenter.parentNote, minHeight: 92)
                }

                if !presenter.marks.isEmpty {
                    marksSummary
                }

                PrimaryButton(title: "Save What Happened",
                              busyTitle: "Saving…",
                              busy: presenter.isSaving) {
                    presenter.save(completion: onClose)
                }
                .padding(.top, NestSpace.s)
            }

            if presenter.celebrate {
                CelebrationOverlay()
            }
        }
    }

    private var summary: some View {
        NestPanel(label: "the evening", glow: true) {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                HStack(alignment: .top, spacing: NestSpace.m) {
                    if let title = presenter.title {
                        PosterView(title: title, width: 62)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(presenter.title?.name ?? presenter.evening?.displayName ?? "Evening")
                            .font(NestFont.titleTight)
                            .foregroundColor(NestColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(presenter.watchedMinutes) minutes watched")
                            .font(NestFont.small)
                            .foregroundColor(NestColor.inkSoft)
                        if let reason = presenter.evening?.watch.stopReason {
                            Text("Stopped early — \(reason.title.lowercased())")
                                .font(NestFont.small)
                                .foregroundColor(NestColor.stop)
                        }
                    }
                    Spacer()
                }
                ViewerTokenRow(viewers: presenter.viewers, size: 28)
            }
        }
    }

    private var marksSummary: some View {
        VStack(alignment: .leading, spacing: NestSpace.m) {
            SectionHead("Marked Moments", subtitle: "Turn any of these into a content note from the title screen.")
            NestCard {
                VStack(alignment: .leading, spacing: NestSpace.s) {
                    ForEach(presenter.marks) { mark in
                        HStack(spacing: NestSpace.m) {
                            Text(mark.timecode)
                                .font(NestFont.figureSmall)
                                .foregroundColor(NestColor.ink)
                                .frame(width: 56, alignment: .leading)
                            NestChip(title: mark.kind.title,
                                     selected: mark.kind.isCautionary,
                                     tint: mark.kind.isCautionary ? NestColor.stop : NestColor.go)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

struct ReactionCard: View {
    let viewer: Viewer
    @Binding var reaction: Reaction

    var body: some View {
        NestCard {
            VStack(alignment: .leading, spacing: NestSpace.m) {
                HStack(spacing: NestSpace.m) {
                    ViewerToken(viewer: viewer, size: 38)
                    Text(viewer.name)
                        .font(NestFont.titleTight)
                        .foregroundColor(NestColor.ink)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: NestSpace.s) {
                    SectionLabel("overall impression")
                    ChipFlow(items: Impression.allCases) { impression in
                        NestChip(title: impression.title,
                                 selected: reaction.impression == impression,
                                 tint: tint(for: impression)) {
                            reaction.impression = reaction.impression == impression ? nil : impression
                        }
                    }
                }

                VStack(alignment: .leading, spacing: NestSpace.s) {
                    NestToggleRow(title: "Watched to the End", isOn: $reaction.watchedToEnd)
                    RowDivider()
                    NestToggleRow(title: "Got Scared", isOn: $reaction.gotScared)
                    RowDivider()
                    NestToggleRow(title: "Asked Questions", isOn: $reaction.askedQuestions)
                    RowDivider()
                    NestToggleRow(title: "Fell Asleep", isOn: $reaction.fellAsleep)
                    RowDivider()
                    NestToggleRow(title: "Wants to Watch Again", isOn: $reaction.wantsAgain)
                }

                FieldShell(label: "Best Moment") {
                    NestTextField(placeholder: "What they talked about afterwards", text: $reaction.bestMoment)
                }

                FieldShell(label: "Private Note") {
                    NestTextArea(placeholder: "Only you see this.", text: $reaction.privateNote, minHeight: 62)
                }
            }
        }
    }

    private func tint(for impression: Impression) -> Color {
        switch impression {
        case .notForThem: return NestColor.stop
        case .okay: return NestColor.inkFaint
        case .good: return NestColor.amber
        case .great, .lovedIt: return NestColor.go
        }
    }
}

/// The app's single celebration: the window bar completes and the nest settles.
/// No confetti, no burst — this is a house at the end of an evening.
struct CelebrationOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seated: CGFloat = 0

    var body: some View {
        ZStack {
            NestColor.ground.opacity(0.94).ignoresSafeArea()
            VStack(spacing: NestSpace.l) {
                NestMark(size: 78, tint: NestColor.go,
                         fill: NestColor.go.opacity(0.12),
                         seat: seated, lineWidth: 2)
                WindowBar(fraction: Double(seated), height: 10)
                    .frame(width: 160)
                nestTracked("evening closed", kern: 1.4)
                    .font(NestFont.label)
                    .foregroundColor(NestColor.go)
            }
        }
        .onAppear {
            if reduceMotion {
                seated = 1
            } else {
                withAnimation(NestMotion.fill) { seated = 1 }
            }
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
