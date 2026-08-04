//  ScreenTimeEngine.swift
//  Screen Nest — weekly screen time.
//
//  Counts only what was actually watched, never what was planned. The app shows
//  the remainder and offers alternatives; it never blocks and never comments on
//  what the number ought to be. The family sets the limit.

import Foundation

struct ScreenTimeWeek: Identifiable, Hashable {
    var id: UUID { viewerId }
    let viewerId: UUID
    let viewerName: String
    let weekStart: Date
    let weekEnd: Date
    let limitMinutes: Int?
    let usedMinutes: Int
    let rolloverMinutes: Int
    let extraMinutes: Int

    /// Limit plus anything carried over or explicitly allowed.
    var allowanceMinutes: Int? {
        guard let limit = limitMinutes else { return nil }
        return limit + rolloverMinutes + extraMinutes
    }

    var remainingMinutes: Int? {
        guard let allowance = allowanceMinutes else { return nil }
        return allowance - usedMinutes
    }

    var fraction: Double {
        guard let allowance = allowanceMinutes, allowance > 0 else { return 0 }
        return min(1.2, Double(usedMinutes) / Double(allowance))
    }

    var isOver: Bool {
        guard let remaining = remainingMinutes else { return false }
        return remaining < 0
    }
}

struct ScreenTimeEntry: Identifiable, Hashable {
    let id: UUID
    let eveningId: UUID
    let date: Date
    let titleName: String
    let minutes: Int
}

enum ScreenTimeEngine {

    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    static func weekEnd(for date: Date, calendar: Calendar = .current) -> Date {
        let start = weekStart(for: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 7, to: start) ?? start
    }

    /// Minutes a viewer actually watched inside a week.
    static func minutesWatched(viewerId: UUID,
                               in document: AppDocument,
                               weekOf date: Date,
                               calendar: Calendar = .current) -> Int {
        let start = weekStart(for: date, calendar: calendar)
        let end = weekEnd(for: date, calendar: calendar)
        return document.evenings.reduce(0) { total, evening in
            guard evening.viewerIds.contains(viewerId),
                  evening.date >= start, evening.date < end,
                  evening.state == .completed || evening.state == .awaitingReactions
            else { return total }
            return total + watchedMinutes(evening)
        }
    }

    static func entries(viewerId: UUID,
                        in document: AppDocument,
                        weekOf date: Date,
                        calendar: Calendar = .current) -> [ScreenTimeEntry] {
        let start = weekStart(for: date, calendar: calendar)
        let end = weekEnd(for: date, calendar: calendar)
        return document.evenings.compactMap { evening in
            guard evening.viewerIds.contains(viewerId),
                  evening.date >= start, evening.date < end,
                  evening.state == .completed || evening.state == .awaitingReactions
            else { return nil }
            let minutes = watchedMinutes(evening)
            guard minutes > 0 else { return nil }
            return ScreenTimeEntry(id: evening.id,
                                   eveningId: evening.id,
                                   date: evening.date,
                                   titleName: evening.titleSnapshot?.name ?? evening.displayName,
                                   minutes: minutes)
        }
        .sorted { $0.date > $1.date }
    }

    /// What the evening genuinely consumed: the timer's reading, capped by the
    /// running time so a forgotten timer cannot invent hours.
    static func watchedMinutes(_ evening: Evening) -> Int {
        let elapsed = evening.watch.elapsed() / 60
        let planned = evening.plannedRuntimeMinutes
        if planned > 0 { return min(elapsed, planned) }
        return elapsed
    }

    static func week(for viewer: Viewer,
                     in document: AppDocument,
                     date: Date = Date(),
                     calendar: Calendar = .current) -> ScreenTimeWeek {
        let start = weekStart(for: date, calendar: calendar)
        let end = weekEnd(for: date, calendar: calendar)
        let limit = viewer.weeklyLimitMinutes ?? (document.profile.defaultWeeklyLimitMinutes > 0
                                                  ? document.profile.defaultWeeklyLimitMinutes : nil)
        let used = minutesWatched(viewerId: viewer.id, in: document, weekOf: date, calendar: calendar)

        var rollover = 0
        if viewer.rolloverAllowed, let limit = limit,
           let previous = calendar.date(byAdding: .day, value: -7, to: date) {
            let previousUsed = minutesWatched(viewerId: viewer.id, in: document, weekOf: previous, calendar: calendar)
            rollover = max(0, limit - previousUsed)
        }

        let extra = document.screenTimeExceptions
            .filter { $0.viewerId == viewer.id && calendar.isDate($0.weekStart, inSameDayAs: start) }
            .reduce(0) { $0 + $1.extraMinutes }

        return ScreenTimeWeek(viewerId: viewer.id,
                              viewerName: viewer.name,
                              weekStart: start,
                              weekEnd: end,
                              limitMinutes: limit,
                              usedMinutes: used,
                              rolloverMinutes: rollover,
                              extraMinutes: extra)
    }

    static func allWeeks(in document: AppDocument, date: Date = Date()) -> [ScreenTimeWeek] {
        document.viewers
            .filter { !$0.role.isGrownUp }
            .map { week(for: $0, in: document, date: date) }
    }

    /// Remaining minutes keyed by viewer, for the suitability check.
    static func remainingByViewer(in document: AppDocument, date: Date = Date()) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for viewer in document.viewers where !viewer.role.isGrownUp {
            let week = week(for: viewer, in: document, date: date)
            if let remaining = week.remainingMinutes {
                map[viewer.id] = remaining
            }
        }
        return map
    }

    /// Past weeks with any activity, newest first.
    static func history(for viewer: Viewer,
                        in document: AppDocument,
                        weeks: Int = 8,
                        from date: Date = Date(),
                        calendar: Calendar = .current) -> [ScreenTimeWeek] {
        (0..<weeks).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -7 * offset, to: date) else { return nil }
            let week = week(for: viewer, in: document, date: day, calendar: calendar)
            return week.usedMinutes > 0 || offset == 0 ? week : nil
        }
    }
}
