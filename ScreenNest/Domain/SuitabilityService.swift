//  SuitabilityService.swift
//  Screen Nest
//
//  Assembles the input the engine needs out of the stored document, so Home,
//  Pick for Tonight, the wizard and the check screen all reason from exactly
//  the same facts.

import Foundation

struct SuitabilityService {

    let store: DataStore

    /// Viewers used when no evening has been chosen yet: everyone in the house.
    func defaultViewers() -> [Viewer] {
        store.viewers
    }

    func window(for viewers: [Viewer], on date: Date = Date(), setup: WindowSetup? = nil) -> EveningWindow {
        var resolved = setup ?? store.profile.defaultWindow(on: date)
        // The earliest bedtime in the room governs the evening.
        let overrides = viewers.compactMap { $0.bedtimeOverride }
        if let earliest = overrides.min(by: { $0.minutesFromMidnight < $1.minutesFromMidnight }),
           earliest.minutesFromMidnight < resolved.bedtime.minutesFromMidnight {
            resolved.bedtime = earliest
        }
        return WindowEngine.window(setup: resolved, now: date)
    }

    func evaluate(title: Title,
                  viewers: [Viewer],
                  date: Date = Date(),
                  window: EveningWindow? = nil,
                  runtimeOverride: Int? = nil,
                  alreadyPlannedTonight: Int = 0) -> SuitabilityResult {

        let resolvedWindow = window ?? self.window(for: viewers, on: date)
        let document = store.document

        let context = SuitabilityContext(
            title: title,
            viewers: viewers,
            rules: store.activeRules,
            profile: store.profile,
            window: resolvedWindow,
            date: date,
            runtimeOverride: runtimeOverride,
            previousMarks: store.previousMarks(forTitle: title.id),
            warningNotes: store.warningNotes(for: title.id),
            watchCount: store.watchCount(forTitle: title.id),
            enthusiasts: store.enthusiasts(forTitle: title.id),
            screenTimeRemaining: ScreenTimeEngine.remainingByViewer(in: document, date: date),
            titlesAlreadyPlannedTonight: alreadyPlannedTonight,
            nextRoomierDay: WindowEngine.nextRoomierDay(profile: store.profile,
                                                        setup: store.profile.defaultWindow(on: date),
                                                        from: date)
        )
        return SuitabilityEngine.evaluate(context)
    }

    /// Every non-archived title, checked against tonight and sorted best first.
    func rank(viewers: [Viewer], date: Date = Date(), window: EveningWindow? = nil) -> [(title: Title, result: SuitabilityResult)] {
        let resolved = window ?? self.window(for: viewers, on: date)
        return store.activeTitles
            .map { title -> (Title, SuitabilityResult) in
                let runtime = title.type.isEpisodic ? (title.nextEpisode?.episode.runtimeMinutes ?? title.runtimeMinutes) : nil
                return (title, evaluate(title: title, viewers: viewers, date: date,
                                        window: resolved, runtimeOverride: runtime))
            }
            .sorted { lhs, rhs in
                if lhs.1.status.rank != rhs.1.status.rank { return lhs.1.status.rank < rhs.1.status.rank }
                // Among equals, the tightest good fit first.
                if lhs.1.fitsWindow != rhs.1.fitsWindow { return lhs.1.fitsWindow }
                return lhs.1.spareMinutes < rhs.1.spareMinutes
            }
            .map { (title: $0.0, result: $0.1) }
    }

    /// The shortest running time in the library — powers "Only 48 Minutes Tonight".
    var shortestRuntime: Int? {
        store.activeTitles.map(\.runtimeMinutes).filter { $0 > 0 }.min()
    }
}
