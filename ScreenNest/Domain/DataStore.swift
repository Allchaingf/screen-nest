//  DataStore.swift
//  Screen Nest
//
//  One JSON document in Application Support, written atomically through a
//  temp-file replace. Posters live beside it as files. Nothing leaves the device.

import Foundation
import Combine
import UIKit

final class DataStore: ObservableObject {

    static let shared = DataStore()

    @Published private(set) var document: AppDocument
    /// Flipped once the first load finishes so screens can show a real loading state.
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var loadError: String?

    private let fileManager = FileManager.default
    private var saveWorkItem: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "nest.datastore.io", qos: .utility)

    // MARK: - Locations

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ScreenNest", isDirectory: true)
    }

    var documentURL: URL { rootDirectory.appendingPathComponent("house.json") }
    var postersDirectory: URL { rootDirectory.appendingPathComponent("Posters", isDirectory: true) }

    var cacheDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ScreenNestCache", isDirectory: true)
    }

    // MARK: - Life cycle

    private init() {
        document = AppDocument()
        createDirectoriesIfNeeded()
        load()
    }

    private func createDirectoriesIfNeeded() {
        for url in [rootDirectory, postersDirectory, cacheDirectory] {
            if !fileManager.fileExists(atPath: url.path) {
                try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    func load() {
        guard fileManager.fileExists(atPath: documentURL.path) else {
            isLoaded = true
            return
        }
        do {
            let data = try Data(contentsOf: documentURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            document = try decoder.decode(AppDocument.self, from: data)
            loadError = nil
        } catch {
            // A corrupt document must never wipe the user's evenings silently.
            let backup = rootDirectory.appendingPathComponent("house-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: documentURL, to: backup)
            loadError = "The saved file could not be read. A copy was kept and the app started fresh."
        }
        isLoaded = true
    }

    // MARK: - Saving

    /// Coalesces bursts of edits into one write.
    func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = document
        let work = DispatchWorkItem { [weak self] in
            self?.write(snapshot)
        }
        saveWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        let snapshot = document
        ioQueue.async { [weak self] in self?.write(snapshot) }
    }

    private func write(_ snapshot: AppDocument) {
        createDirectoriesIfNeeded()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }

        let temp = rootDirectory.appendingPathComponent("house-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: documentURL.path) {
                _ = try fileManager.replaceItemAt(documentURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: documentURL)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
        }
    }

    /// Mutate + persist in one step, on the main queue.
    func mutate(_ change: (inout AppDocument) -> Void) {
        change(&document)
        scheduleSave()
    }

    // MARK: - Profile

    var profile: HouseProfile { document.profile }

    func updateProfile(_ change: (inout HouseProfile) -> Void) {
        mutate { doc in change(&doc.profile) }
    }

    // MARK: - Viewers

    var viewers: [Viewer] {
        document.viewers.sorted { lhs, rhs in
            if lhs.role == rhs.role { return lhs.createdAt < rhs.createdAt }
            return lhs.role.rawValue < rhs.role.rawValue
        }
    }

    var children: [Viewer] { document.viewers.filter { !$0.role.isGrownUp } }
    var adults: [Viewer] { document.viewers.filter { $0.role.isGrownUp } }

    func viewer(id: UUID) -> Viewer? { document.viewers.first { $0.id == id } }
    func viewers(ids: [UUID]) -> [Viewer] { ids.compactMap { viewer(id: $0) } }

    func upsertViewer(_ viewer: Viewer) {
        mutate { doc in
            if let index = doc.viewers.firstIndex(where: { $0.id == viewer.id }) {
                doc.viewers[index] = viewer
            } else {
                doc.viewers.append(viewer)
            }
        }
    }

    func deleteViewer(id: UUID) {
        mutate { doc in
            doc.viewers.removeAll { $0.id == id }
            // Keep history readable: the viewer leaves upcoming evenings only.
            for index in doc.evenings.indices where doc.evenings[index].state != .completed {
                doc.evenings[index].viewerIds.removeAll { $0 == id }
                doc.evenings[index].reactions.removeAll { $0.viewerId == id }
            }
            for index in doc.rules.indices {
                doc.rules[index].appliesTo.removeAll { $0 == id }
            }
        }
    }

    func markSensitivityGrownOut(viewerId: UUID, sensitivityId: UUID) {
        mutate { doc in
            guard let vIndex = doc.viewers.firstIndex(where: { $0.id == viewerId }),
                  let sIndex = doc.viewers[vIndex].sensitivities.firstIndex(where: { $0.id == sensitivityId })
            else { return }
            doc.viewers[vIndex].sensitivities[sIndex].grownOutOn = Date()
        }
    }

    func restoreSensitivity(viewerId: UUID, sensitivityId: UUID) {
        mutate { doc in
            guard let vIndex = doc.viewers.firstIndex(where: { $0.id == viewerId }),
                  let sIndex = doc.viewers[vIndex].sensitivities.firstIndex(where: { $0.id == sensitivityId })
            else { return }
            doc.viewers[vIndex].sensitivities[sIndex].grownOutOn = nil
        }
    }

    // MARK: - Titles

    var titles: [Title] { document.titles }
    var activeTitles: [Title] { document.titles.filter { !$0.isArchived } }

    func title(id: UUID?) -> Title? {
        guard let id = id else { return nil }
        return document.titles.first { $0.id == id }
    }

    func upsertTitle(_ title: Title) {
        var copy = title
        copy.updatedAt = Date()
        mutate { doc in
            if let index = doc.titles.firstIndex(where: { $0.id == copy.id }) {
                doc.titles[index] = copy
            } else {
                doc.titles.append(copy)
            }
        }
    }

    func deleteTitle(id: UUID) {
        mutate { doc in
            if let title = doc.titles.first(where: { $0.id == id }),
               let poster = title.posterFileName {
                try? self.fileManager.removeItem(at: self.postersDirectory.appendingPathComponent(poster))
            }
            doc.titles.removeAll { $0.id == id }
            doc.contentNotes.removeAll { $0.titleId == id }
            // Completed evenings keep their snapshot; only the live link is cleared.
            for index in doc.evenings.indices where doc.evenings[index].titleId == id {
                doc.evenings[index].titleId = nil
            }
        }
    }

    func toggleFavourite(titleId: UUID) {
        mutate { doc in
            guard let index = doc.titles.firstIndex(where: { $0.id == titleId }) else { return }
            doc.titles[index].isFavourite.toggle()
            doc.titles[index].updatedAt = Date()
        }
    }

    func setArchived(titleId: UUID, archived: Bool) {
        mutate { doc in
            guard let index = doc.titles.firstIndex(where: { $0.id == titleId }) else { return }
            doc.titles[index].isArchived = archived
            doc.titles[index].updatedAt = Date()
        }
    }

    func updateSeriesPosition(titleId: UUID, season: Int, episode: Int) {
        mutate { doc in
            guard let index = doc.titles.firstIndex(where: { $0.id == titleId }) else { return }
            doc.titles[index].seriesPosition = SeriesPosition(seasonNumber: season,
                                                              episodeNumber: episode,
                                                              lastWatched: Date())
            doc.titles[index].updatedAt = Date()
        }
    }

    // MARK: - Rules

    var rules: [HouseRule] { document.rules }
    var activeRules: [HouseRule] { document.rules.filter { $0.isActive } }

    func rule(id: UUID) -> HouseRule? { document.rules.first { $0.id == id } }

    func upsertRule(_ rule: HouseRule, changeNote: String) {
        mutate { doc in
            if let index = doc.rules.firstIndex(where: { $0.id == rule.id }) {
                doc.rules[index] = rule
            } else {
                doc.rules.append(rule)
            }
            doc.ruleHistory.append(RuleHistoryEntry(ruleId: rule.id,
                                                    ruleTitle: rule.type.title,
                                                    change: changeNote))
        }
    }

    func retireRule(id: UUID) {
        mutate { doc in
            guard let index = doc.rules.firstIndex(where: { $0.id == id }) else { return }
            doc.rules[index].isActive = false
            doc.rules[index].retiredAt = Date()
            doc.ruleHistory.append(RuleHistoryEntry(ruleId: id,
                                                    ruleTitle: doc.rules[index].type.title,
                                                    change: "Retired"))
        }
    }

    func reinstateRule(id: UUID) {
        mutate { doc in
            guard let index = doc.rules.firstIndex(where: { $0.id == id }) else { return }
            doc.rules[index].isActive = true
            doc.rules[index].retiredAt = nil
            doc.ruleHistory.append(RuleHistoryEntry(ruleId: id,
                                                    ruleTitle: doc.rules[index].type.title,
                                                    change: "Reinstated"))
        }
    }

    func deleteRule(id: UUID) {
        mutate { doc in
            if let rule = doc.rules.first(where: { $0.id == id }) {
                doc.ruleHistory.append(RuleHistoryEntry(ruleId: id,
                                                        ruleTitle: rule.type.title,
                                                        change: "Removed"))
            }
            doc.rules.removeAll { $0.id == id }
        }
    }

    // MARK: - Evenings

    var evenings: [Evening] { document.evenings }

    var completedEvenings: [Evening] {
        document.evenings.filter { $0.state == .completed }.sorted { $0.date > $1.date }
    }

    var unfinishedEvening: Evening? {
        document.evenings.first { $0.state == .watching }
    }

    var draftEvening: Evening? {
        document.evenings
            .filter { $0.state == .draft }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func evening(id: UUID?) -> Evening? {
        guard let id = id else { return nil }
        return document.evenings.first { $0.id == id }
    }

    func upsertEvening(_ evening: Evening) {
        mutate { doc in
            if let index = doc.evenings.firstIndex(where: { $0.id == evening.id }) {
                doc.evenings[index] = evening
            } else {
                doc.evenings.append(evening)
            }
        }
    }

    func deleteEvening(id: UUID) {
        mutate { doc in doc.evenings.removeAll { $0.id == id } }
    }

    // MARK: - Content notes

    var contentNotes: [ContentNote] { document.contentNotes }

    func notes(for titleId: UUID) -> [ContentNote] {
        document.contentNotes
            .filter { $0.titleId == titleId }
            .sorted { ($0.timestampSeconds ?? 0) < ($1.timestampSeconds ?? 0) }
    }

    func warningNotes(for titleId: UUID) -> [ContentNote] {
        notes(for: titleId).filter { $0.warnBeforeWatching }
    }

    func upsertNote(_ note: ContentNote) {
        mutate { doc in
            if let index = doc.contentNotes.firstIndex(where: { $0.id == note.id }) {
                doc.contentNotes[index] = note
            } else {
                doc.contentNotes.append(note)
            }
        }
    }

    func deleteNote(id: UUID) {
        mutate { doc in doc.contentNotes.removeAll { $0.id == id } }
    }

    // MARK: - Screen time exceptions

    func addScreenTimeException(_ exception: ScreenTimeException) {
        mutate { doc in doc.screenTimeExceptions.append(exception) }
    }

    func deleteScreenTimeException(id: UUID) {
        mutate { doc in doc.screenTimeExceptions.removeAll { $0.id == id } }
    }

    // MARK: - Bulk operations (Settings)

    func replaceDocument(_ newDocument: AppDocument) {
        document = newDocument
        saveNow()
    }

    func clearHistory() {
        mutate { doc in
            doc.evenings.removeAll { $0.state == .completed }
        }
        saveNow()
    }

    func deleteAllData() {
        try? fileManager.removeItem(at: postersDirectory)
        try? fileManager.removeItem(at: cacheDirectory)
        createDirectoriesIfNeeded()
        document = AppDocument()
        saveNow()
    }

    // MARK: - Derived reads used across modules

    /// Every completed or in-progress evening that used this title.
    func evenings(forTitle titleId: UUID) -> [Evening] {
        document.evenings.filter { $0.titleId == titleId }
    }

    func watchCount(forTitle titleId: UUID) -> Int {
        document.evenings.filter { $0.titleId == titleId && $0.state == .completed }.count
    }

    func lastWatched(titleId: UUID) -> Date? {
        document.evenings
            .filter { $0.titleId == titleId && $0.state == .completed }
            .compactMap { $0.completedAt ?? $0.date }
            .max()
    }

    /// Marks recorded during earlier viewings of a title.
    func previousMarks(forTitle titleId: UUID) -> [MarkedMoment] {
        document.evenings
            .filter { $0.titleId == titleId }
            .flatMap { $0.watch.marks }
            .sorted { $0.atSeconds < $1.atSeconds }
    }

    /// Viewers who finished a title and asked for it again.
    func enthusiasts(forTitle titleId: UUID) -> [Viewer] {
        let ids = document.evenings
            .filter { $0.titleId == titleId && $0.state == .completed }
            .flatMap { $0.reactions }
            .filter { $0.wantsAgain }
            .map { $0.viewerId }
        return Array(Set(ids)).compactMap { viewer(id: $0) }
    }
}
