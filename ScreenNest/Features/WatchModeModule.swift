//  WatchModeModule.swift
//  Screen Nest — Watch Mode.
//
//  A warm dark room, big buttons, nothing else. The clock is a display over
//  stored anchors, not a source of truth: it survives backgrounding, and the
//  film is never marked watched by a timer. The parent ends the evening.

import SwiftUI

final class WatchPresenter: ObservableObject {
    @Published private(set) var evening: Evening?
    @Published var showMarkPicker = false
    @Published var showStopReasons = false
    @Published var lastMark: MarkedMoment?
    @Published var confirmingFinish = false

    private let store: DataStore
    let eveningId: UUID

    init(eveningId: UUID, store: DataStore) {
        self.eveningId = eveningId
        self.store = store
        self.evening = store.evening(id: eveningId)
    }

    var title: Title? { store.title(id: evening?.titleId) }
    var viewers: [Viewer] { store.viewers(ids: evening?.viewerIds ?? []) }

    var runtimeSeconds: Int {
        max(1, (evening?.plannedRuntimeMinutes ?? 0) * 60)
    }

    var previousMarks: [MarkedMoment] {
        guard let titleId = evening?.titleId else { return [] }
        return store.previousMarks(forTitle: titleId).filter { mark in
            !(evening?.watch.marks.contains { $0.id == mark.id } ?? false)
        }
    }

    func elapsed(at date: Date) -> Int {
        evening?.watch.elapsed(at: date) ?? 0
    }

    func remaining(at date: Date) -> Int {
        max(0, runtimeSeconds - elapsed(at: date))
    }

    var isRunning: Bool { evening?.watch.isRunning ?? false }
    var hasStarted: Bool { evening?.watch.startedAt != nil }

    /// The nearest earlier mark from a previous viewing, surfaced as it approaches.
    func upcomingWarning(at date: Date) -> MarkedMoment? {
        let now = elapsed(at: date)
        return previousMarks
            .filter { $0.kind.isCautionary && $0.atSeconds >= now && $0.atSeconds - now <= 120 }
            .min { $0.atSeconds < $1.atSeconds }
    }

    // MARK: Intents

    private func mutate(_ change: (inout Evening) -> Void) {
        guard var current = store.evening(id: eveningId) else { return }
        change(&current)
        store.upsertEvening(current)
        evening = current
    }

    func start() {
        mutate { evening in
            if evening.watch.startedAt == nil {
                evening.watch.startedAt = Date()
                evening.watch.accumulatedSeconds = evening.watch.resumeFromSeconds
            }
            evening.watch.isPaused = false
            evening.watch.lastResumedAt = Date()
            evening.state = .watching
        }
        ScreenIdle.disableSleep(true)
        NestHaptics.firm()
    }

    func pause() {
        mutate { evening in
            guard !evening.watch.isPaused else { return }
            evening.watch.accumulatedSeconds = evening.watch.elapsed()
            evening.watch.isPaused = true
            evening.watch.lastResumedAt = nil
        }
        ScreenIdle.disableSleep(false)
        NestHaptics.tap()
    }

    func resume() {
        mutate { evening in
            evening.watch.isPaused = false
            evening.watch.lastResumedAt = Date()
        }
        ScreenIdle.disableSleep(true)
        NestHaptics.tap()
    }

    func snackBreak() {
        pause()
        mutate { evening in
            evening.window.snackBreakMinutes += 10
        }
        NestHaptics.firm()
    }

    func mark(_ kind: MomentKind) {
        let at = elapsed(at: Date())
        let moment = MarkedMoment(atSeconds: at, kind: kind)
        mutate { evening in evening.watch.marks.append(moment) }
        lastMark = moment
        showMarkPicker = false
        NestHaptics.success()
    }

    func stopEarly(_ reason: StopReason) {
        let at = elapsed(at: Date())
        mutate { evening in
            evening.watch.accumulatedSeconds = at
            evening.watch.isPaused = true
            evening.watch.lastResumedAt = nil
            evening.watch.stopReason = reason
            evening.watch.stoppedAtSeconds = at
            evening.watch.resumeFromSeconds = at
            evening.outcome = .stoppedEarly
            evening.state = .awaitingReactions
            evening.completedAt = Date()
        }
        ScreenIdle.disableSleep(false)
        showStopReasons = false
        NestHaptics.warning()
        NotificationService.shared.reschedule(for: store.document)
    }

    func finish() {
        let at = elapsed(at: Date())
        mutate { evening in
            evening.watch.accumulatedSeconds = at
            evening.watch.isPaused = true
            evening.watch.lastResumedAt = nil
            evening.outcome = .finished
            evening.state = .awaitingReactions
            evening.completedAt = Date()
        }
        // A series evening moves the position on by one episode.
        if let evening = evening, let episode = evening.episodeRef, let titleId = evening.titleId {
            store.updateSeriesPosition(titleId: titleId,
                                       season: episode.seasonNumber,
                                       episode: episode.episodeNumber)
        }
        ScreenIdle.disableSleep(false)
        NestHaptics.success()
        NotificationService.shared.reschedule(for: store.document)
    }

    /// Keeps the evening resumable on another day without ending it.
    func leaveForNow() {
        if isRunning { pause() }
        ScreenIdle.disableSleep(false)
        mutate { evening in
            evening.watch.resumeFromSeconds = evening.watch.accumulatedSeconds
            evening.state = .watching
        }
        NotificationService.shared.reschedule(for: store.document)
    }
}

struct WatchModeView: View {
    let eveningId: UUID

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var presenter: WatchPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lightsDown = false

    init(eveningId: UUID) {
        self.eveningId = eveningId
        _presenter = StateObject(wrappedValue: WatchPresenter(eveningId: eveningId, store: .shared))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [NestColor.watchGround, NestColor.watchGroundLo],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .opacity(lightsDown ? 1 : 0)

            if presenter.evening == nil {
                VStack(spacing: NestSpace.l) {
                    Text("This evening is no longer available.")
                        .font(NestFont.body)
                        .foregroundColor(NestColor.watchInk)
                    Button("Close") { router.watchEveningId = nil }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(NestSpace.xl)
            } else {
                content
            }
        }
        .opacity(lightsDown ? 1 : 0)
        .onAppear {
            // The lights going down in the room.
            if reduceMotion {
                lightsDown = true
            } else {
                withAnimation(.easeInOut(duration: 0.4)) { lightsDown = true }
            }
        }
        .onDisappear {
            // Nothing keeps running once this screen is gone.
            ScreenIdle.disableSleep(false)
        }
    }

    private var content: some View {
        TimelineView(.periodic(from: .now, by: presenter.isRunning ? 1 : 60)) { context in
            let now = context.date
            let elapsed = presenter.elapsed(at: now)
            let remaining = presenter.remaining(at: now)

            VStack(spacing: 0) {
                header

                Spacer(minLength: 0)

                VStack(spacing: NestSpace.s) {
                    nestTracked("elapsed", kern: 1.2)
                        .font(NestFont.label)
                        .foregroundColor(NestColor.watchInkSoft)

                    Text(TimeFormat.clockLong(seconds: elapsed))
                        .font(NestFont.watchClock)
                        .foregroundColor(NestColor.watchInk)

                    Text("\(TimeFormat.clockLong(seconds: remaining)) remaining")
                        .font(NestFont.watchSub)
                        .foregroundColor(NestColor.watchInkSoft)
                }

                progressStrip(elapsed: elapsed)
                    .padding(.top, NestSpace.xl)
                    .padding(.horizontal, NestSpace.gutter)

                if let warning = presenter.upcomingWarning(at: now) {
                    warningBanner(warning)
                        .padding(.top, NestSpace.l)
                        .padding(.horizontal, NestSpace.gutter)
                }

                if let mark = presenter.lastMark {
                    Text("Marked \(mark.kind.title.lowercased()) at \(mark.timecode).")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.watchAmber)
                        .padding(.top, NestSpace.m)
                }

                Spacer(minLength: 0)

                controls
                    .padding(.horizontal, NestSpace.gutter)
                    .padding(.bottom, NestSpace.xl)
            }
        }
        .confirmationDialog("Mark a Moment", isPresented: $presenter.showMarkPicker, titleVisibility: .visible) {
            ForEach(MomentKind.allCases) { kind in
                Button(kind.title) { presenter.mark(kind) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kept on the title and shown next time you consider it.")
        }
        .confirmationDialog("Why did it stop?", isPresented: $presenter.showStopReasons, titleVisibility: .visible) {
            ForEach(StopReason.allCases) { reason in
                Button(reason.title) {
                    presenter.stopEarly(reason)
                    router.openAfterWatch(presenter.eveningId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The place you stopped is saved, so the evening can be picked up another day.")
        }
        .alert("Finished?", isPresented: $presenter.confirmingFinish) {
            Button("Not yet", role: .cancel) {}
            Button("Finished") {
                presenter.finish()
                router.openAfterWatch(presenter.eveningId)
            }
        } message: {
            Text("The timer never decides this. Only say finished when it actually ended.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                nestTracked("started at \(startedAtText)", kern: 1.0)
                    .font(NestFont.label)
                    .foregroundColor(NestColor.watchInkSoft)
                Text(presenter.title?.name ?? presenter.evening?.displayName ?? "Evening")
                    .font(NestFont.watchTitle)
                    .foregroundColor(NestColor.watchInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let episode = presenter.evening?.episodeRef {
                    Text("\(episode.label) — \(episode.name)")
                        .font(NestFont.small)
                        .foregroundColor(NestColor.watchPlum)
                }
            }
            Spacer()
            Button {
                NestHaptics.tap()
                presenter.leaveForNow()
                router.watchEveningId = nil
            } label: {
                nestTracked("leave for now", kern: 0.9)
                    .font(NestFont.label)
                    .foregroundColor(NestColor.watchInkSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NestSpace.gutter)
        .padding(.top, NestSpace.xl)
    }

    private var startedAtText: String {
        guard let started = presenter.evening?.watch.startedAt else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: started)
    }

    private func progressStrip(elapsed: Int) -> some View {
        VStack(alignment: .leading, spacing: NestSpace.s) {
            MinuteTicks(count: 25, height: 5, emphasisEvery: 6, colour: NestColor.watchInkSoft.opacity(0.4))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NestColor.watchInkSoft.opacity(0.18))
                        .frame(height: 8)
                    Capsule()
                        .fill(NestColor.watchAmber)
                        .frame(width: geo.size.width * min(1, CGFloat(elapsed) / CGFloat(presenter.runtimeSeconds)),
                               height: 8)

                    // Marks made this evening, and warnings from before.
                    ForEach(presenter.evening?.watch.marks ?? []) { mark in
                        Circle()
                            .fill(mark.kind.isCautionary ? NestColor.stop : NestColor.watchPlum)
                            .frame(width: 7, height: 7)
                            .offset(x: geo.size.width * CGFloat(mark.atSeconds) / CGFloat(presenter.runtimeSeconds) - 3.5)
                    }
                    ForEach(presenter.previousMarks) { mark in
                        Capsule()
                            .fill(NestColor.watchInk.opacity(0.5))
                            .frame(width: 2, height: 16)
                            .offset(x: geo.size.width * CGFloat(mark.atSeconds) / CGFloat(presenter.runtimeSeconds) - 1)
                    }
                }
                .frame(height: 20)
            }
            .frame(height: 20)
        }
    }

    private func warningBanner(_ mark: MarkedMoment) -> some View {
        HStack(spacing: NestSpace.m) {
            ReasonSymbolGlyph(symbol: .history, tint: NestColor.watchAmber, size: 18)
            Text("Last time you marked a \(mark.kind.title.lowercased()) moment at \(mark.timecode).")
                .font(NestFont.small)
                .foregroundColor(NestColor.watchInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NestSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                .fill(NestColor.watchAmber.opacity(0.14))
        )
    }

    private var controls: some View {
        VStack(spacing: NestSpace.m) {
            if !presenter.hasStarted {
                bigButton(title: "Start Watching", tint: NestColor.watchAmber, filled: true) {
                    presenter.start()
                }
            } else if presenter.isRunning {
                bigButton(title: "Pause", tint: NestColor.watchAmber, filled: true) {
                    presenter.pause()
                }
            } else {
                bigButton(title: resumeTitle, tint: NestColor.watchAmber, filled: true) {
                    presenter.resume()
                }
            }

            HStack(spacing: NestSpace.m) {
                smallButton(title: "Snack Break") { presenter.snackBreak() }
                smallButton(title: "Mark a Moment") {
                    NestHaptics.tap()
                    presenter.showMarkPicker = true
                }
            }

            HStack(spacing: NestSpace.m) {
                smallButton(title: "Stopped Early", tint: NestColor.stop) {
                    NestHaptics.tap()
                    presenter.showStopReasons = true
                }
                smallButton(title: "Finished", tint: NestColor.go) {
                    NestHaptics.tap()
                    presenter.confirmingFinish = true
                }
            }
        }
    }

    private var resumeTitle: String {
        let at = TimeFormat.clock(seconds: presenter.evening?.watch.accumulatedSeconds ?? 0)
        return (presenter.evening?.watch.accumulatedSeconds ?? 0) > 0 ? "Resume From \(at)" : "Resume"
    }

    private func bigButton(title: String, tint: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NestFont.watchButton)
                .foregroundColor(filled ? NestColor.watchGround : tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                        .fill(filled ? tint : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NestRadius.card, style: .continuous)
                        .stroke(tint, lineWidth: filled ? 0 : NestStroke.mark)
                )
        }
        .buttonStyle(.plain)
    }

    private func smallButton(title: String, tint: Color = NestColor.watchInk, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NestFont.heading)
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: NestRadius.button, style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: NestStroke.mark)
                )
        }
        .buttonStyle(.plain)
    }
}
