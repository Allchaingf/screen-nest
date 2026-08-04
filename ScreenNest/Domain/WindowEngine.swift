//  WindowEngine.swift
//  Screen Nest — the evening window.
//
//  The formula is shown to the parent verbatim, because a number nobody can
//  check is a number nobody trusts:
//
//      Window = bedtime − now − settling time − expected pauses
//
//  Snack break and buffer are part of "everything around the film" and are
//  subtracted with the rest.

import Foundation

struct WindowLine: Identifiable, Hashable {
    var id: String { label }
    let label: String
    /// Signed minutes as they appear in the sum.
    let minutes: Int
    let isTotal: Bool

    init(_ label: String, _ minutes: Int, isTotal: Bool = false) {
        self.label = label
        self.minutes = minutes
        self.isTotal = isTotal
    }
}

struct EveningWindow: Hashable {
    /// bedtime − now, before anything is taken off.
    let minutesToBedtime: Int
    let settlingMinutes: Int
    let pauseMinutes: Int
    let snackMinutes: Int
    let bufferMinutes: Int
    /// What is genuinely left for the film itself. Never negative.
    let filmMinutes: Int
    let bedtime: TimeOfDay
    let referenceTime: TimeOfDay
    let bedtimeHasPassed: Bool

    var overheadMinutes: Int { settlingMinutes + pauseMinutes + snackMinutes + bufferMinutes }

    /// The sum, line by line, exactly as the screen prints it.
    var breakdown: [WindowLine] {
        var lines: [WindowLine] = [
            WindowLine("Bedtime \(bedtime.display) − now \(referenceTime.display)", minutesToBedtime),
            WindowLine("Settling", -settlingMinutes)
        ]
        if pauseMinutes > 0 { lines.append(WindowLine("Expected pauses", -pauseMinutes)) }
        if snackMinutes > 0 { lines.append(WindowLine("Snack break", -snackMinutes)) }
        if bufferMinutes > 0 { lines.append(WindowLine("Buffer", -bufferMinutes)) }
        lines.append(WindowLine("Window for the film", filmMinutes, isTotal: true))
        return lines
    }

    /// Progress of the evening towards bedtime, for the filling bar. 0…1.
    func fillFraction(spanMinutes: Int = 300) -> Double {
        guard spanMinutes > 0 else { return 0 }
        let used = max(0, spanMinutes - minutesToBedtime)
        return min(1, max(0, Double(used) / Double(spanMinutes)))
    }

    var sentence: String {
        if bedtimeHasPassed {
            return "Bedtime \(bedtime.display) has already passed."
        }
        if filmMinutes <= 0 {
            return "Bedtime \(bedtime.display). Once settling and pauses are taken off, there is no room for a film tonight."
        }
        return "Bedtime \(bedtime.display). Now \(referenceTime.display). Settling \(settlingMinutes) minutes. Window for the film: \(filmMinutes) minutes."
    }
}

enum WindowEngine {

    /// The window as of `now`, for a given setup.
    static func window(setup: WindowSetup,
                       now: Date = Date(),
                       calendar: Calendar = .current) -> EveningWindow {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let reference = TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        return window(setup: setup, referenceTime: reference)
    }

    /// The window measured from an arbitrary start time (used by planned evenings).
    static func window(setup: WindowSetup, referenceTime: TimeOfDay) -> EveningWindow {
        let raw = setup.bedtime.minutesFromMidnight - referenceTime.minutesFromMidnight
        let hasPassed = raw <= 0
        let toBedtime = max(0, raw)
        let pauses = setup.pauseCount * setup.pauseLengthMinutes
        let film = max(0, toBedtime - setup.settlingMinutes - pauses - setup.snackBreakMinutes - setup.bufferMinutes)

        return EveningWindow(
            minutesToBedtime: toBedtime,
            settlingMinutes: setup.settlingMinutes,
            pauseMinutes: pauses,
            snackMinutes: setup.snackBreakMinutes,
            bufferMinutes: setup.bufferMinutes,
            filmMinutes: film,
            bedtime: setup.bedtime,
            referenceTime: referenceTime,
            bedtimeHasPassed: hasPassed
        )
    }

    /// The window this evening would have on the next weekend day — used to say
    /// "It fits on Saturday" instead of just refusing.
    static func nextRoomierDay(profile: HouseProfile,
                               setup: WindowSetup,
                               from date: Date = Date(),
                               calendar: Calendar = .current) -> (dayName: String, minutes: Int)? {
        var probe = setup
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            probe.bedtime = profile.bedtime(on: day, calendar: calendar)
            // On a free day the evening realistically starts at the same hour.
            let result = window(setup: probe, referenceTime: TimeOfDay(hour: 18, minute: 0))
            if calendar.isDateInWeekend(day) {
                return (TimeFormat.weekdayFormatter.string(from: day), result.filmMinutes)
            }
        }
        return nil
    }

    /// Where a split lands: two sittings that each respect the shortest attention span.
    static func splitSuggestion(runtimeMinutes: Int, windowMinutes: Int, attentionSpan: Int) -> (first: Int, second: Int)? {
        guard runtimeMinutes > 0 else { return nil }
        let cap = max(15, min(windowMinutes, attentionSpan))
        guard runtimeMinutes > cap else { return nil }
        let first = min(cap, runtimeMinutes - 10)
        return (first, runtimeMinutes - first)
    }
}
