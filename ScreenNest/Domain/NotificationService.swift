//  NotificationService.swift
//  Screen Nest
//
//  Four local reminders, each switched separately in Settings. Nothing is
//  scheduled until the parent has read what it is for and said yes.

import Foundation
import UserNotifications

enum NestReminder: String, CaseIterable, Identifiable {
    case eveningStartsSoon
    case reactionsNotRecorded
    case unfinishedFilmWaiting
    case weeklyScreenTimeReset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eveningStartsSoon:     return "Evening Starts Soon"
        case .reactionsNotRecorded:  return "Reactions Not Recorded"
        case .unfinishedFilmWaiting: return "Unfinished Film Waiting"
        case .weeklyScreenTimeReset: return "Weekly Screen Time Reset"
        }
    }

    var explanation: String {
        switch self {
        case .eveningStartsSoon:
            return "Fifteen minutes before a planned evening, so the settling time is real."
        case .reactionsNotRecorded:
            return "The morning after, if nobody wrote down what happened. Details fade fast."
        case .unfinishedFilmWaiting:
            return "When a film was stopped part-way and never picked up again."
        case .weeklyScreenTimeReset:
            return "When the weekly count starts again, so the remainder means something."
        }
    }

    var defaultsKey: String {
        switch self {
        case .eveningStartsSoon:     return NestDefaults.notifEveningSoon
        case .reactionsNotRecorded:  return NestDefaults.notifReactions
        case .unfinishedFilmWaiting: return NestDefaults.notifUnfinished
        case .weeklyScreenTimeReset: return NestDefaults.notifWeeklyReset
        }
    }
}

final class NotificationService: ObservableObject {

    static let shared = NotificationService()

    @Published private(set) var authorisation: UNAuthorizationStatus = .notDetermined

    private let centre = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private init() {
        refreshAuthorisation()
    }

    func refreshAuthorisation() {
        centre.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorisation = settings.authorizationStatus
            }
        }
    }

    var isAuthorised: Bool {
        authorisation == .authorized || authorisation == .provisional
    }

    func requestAuthorisation(completion: @escaping (Bool) -> Void) {
        centre.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.defaults.set(granted, forKey: NestDefaults.notifAuthorised)
                self?.refreshAuthorisation()
                completion(granted)
            }
        }
    }

    func isEnabled(_ reminder: NestReminder) -> Bool {
        defaults.object(forKey: reminder.defaultsKey) as? Bool ?? false
    }

    func setEnabled(_ reminder: NestReminder, _ enabled: Bool, document: AppDocument) {
        defaults.set(enabled, forKey: reminder.defaultsKey)
        if enabled {
            reschedule(for: document)
        } else {
            cancel(reminder)
        }
    }

    // MARK: - Scheduling

    private func identifier(_ reminder: NestReminder, suffix: String = "") -> String {
        suffix.isEmpty ? "nest.\(reminder.rawValue)" : "nest.\(reminder.rawValue).\(suffix)"
    }

    func cancel(_ reminder: NestReminder) {
        centre.getPendingNotificationRequests { [weak self] requests in
            guard let self = self else { return }
            let prefix = "nest.\(reminder.rawValue)"
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            self.centre.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelAll() {
        centre.removeAllPendingNotificationRequests()
    }

    /// Re-derives every pending reminder from the current document. Called after
    /// any change that could move a date.
    func reschedule(for document: AppDocument) {
        guard isAuthorised else { return }
        cancelAll()

        if isEnabled(.eveningStartsSoon) { scheduleEveningReminders(document) }
        if isEnabled(.reactionsNotRecorded) { scheduleReactionReminders(document) }
        if isEnabled(.unfinishedFilmWaiting) { scheduleUnfinishedReminder(document) }
        if isEnabled(.weeklyScreenTimeReset) { scheduleWeeklyReset(document) }
    }

    private func scheduleEveningReminders(_ document: AppDocument) {
        let calendar = Calendar.current
        let upcoming = document.evenings.filter { $0.state == .planned }
        for evening in upcoming.prefix(12) {
            let start = evening.startTime.date(on: evening.date, calendar: calendar)
            guard let fire = calendar.date(byAdding: .minute, value: -15, to: start), fire > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Evening starts soon"
            let name = evening.titleSnapshot?.name ?? evening.displayName
            content.body = "\(name) at \(evening.startTime.display). Settling time starts now."
            content.sound = .default

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            centre.add(UNNotificationRequest(identifier: identifier(.eveningStartsSoon, suffix: evening.id.uuidString),
                                             content: content, trigger: trigger))
        }
    }

    private func scheduleReactionReminders(_ document: AppDocument) {
        let calendar = Calendar.current
        let waiting = document.evenings.filter { $0.state == .awaitingReactions }
        for evening in waiting.prefix(6) {
            guard let morning = calendar.date(bySettingHour: 9, minute: 30, second: 0,
                                              of: calendar.date(byAdding: .day, value: 1, to: evening.date) ?? evening.date),
                  morning > Date()
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Reactions not recorded"
            content.body = "\(evening.titleSnapshot?.name ?? evening.displayName) — what actually happened? It fades by tomorrow."
            content.sound = .default

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: morning)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            centre.add(UNNotificationRequest(identifier: identifier(.reactionsNotRecorded, suffix: evening.id.uuidString),
                                             content: content, trigger: trigger))
        }
    }

    private func scheduleUnfinishedReminder(_ document: AppDocument) {
        guard let evening = document.evenings.first(where: { $0.state == .watching }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Unfinished film waiting"
        let at = TimeFormat.clock(seconds: evening.watch.elapsed())
        content.body = "\(evening.titleSnapshot?.name ?? evening.displayName) is paused at \(at). Pick it up when it suits."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60 * 24, repeats: false)
        centre.add(UNNotificationRequest(identifier: identifier(.unfinishedFilmWaiting, suffix: evening.id.uuidString),
                                         content: content, trigger: trigger))
    }

    private func scheduleWeeklyReset(_ document: AppDocument) {
        let content = UNMutableNotificationContent()
        content.title = "Weekly screen time reset"
        content.body = "The week has started again. The remaining minutes are back to your limit."
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = Calendar.current.firstWeekday
        comps.hour = 8
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        centre.add(UNNotificationRequest(identifier: identifier(.weeklyScreenTimeReset),
                                         content: content, trigger: trigger))
    }
}
