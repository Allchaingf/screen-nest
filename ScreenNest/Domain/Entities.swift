//  Entities.swift
//  Screen Nest — VIPER entity layer.
//
//  Every type decodes defensively: a document written by an older build must
//  degrade into defaults rather than throw. Nothing here knows about SwiftUI.

import Foundation

// MARK: - Migration-safe decoding helper

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `fallback` when the key is absent,
    /// null, or of an unexpected shape. Keeps old documents readable forever.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - Time of day

struct TimeOfDay: Codable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    init(minutesFromMidnight: Int) {
        let clamped = ((minutesFromMidnight % 1440) + 1440) % 1440
        self.hour = clamped / 60
        self.minute = clamped % 60
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hour = max(0, min(23, c.value(.hour, 20)))
        self.minute = max(0, min(59, c.value(.minute, 30)))
    }

    var minutesFromMidnight: Int { hour * 60 + minute }

    var display: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Concrete `Date` for this time of day on the given day.
    func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static let defaultWeeknight = TimeOfDay(hour: 20, minute: 30)
    static let defaultWeekend = TimeOfDay(hour: 21, minute: 30)
}

// MARK: - Content aspects
//
// Deliberately ONE vocabulary: what a title contains and what a viewer is
// sensitive to are the same twelve words, so a match is exact rather than fuzzy.
// Two extra aspects exist for house rules only.

enum ContentAspect: String, Codable, CaseIterable, Identifiable, Hashable {
    case loudNoises
    case jumpScares
    case darkness
    case animalInDanger
    case parentSeparation
    case characterDeath
    case bullying
    case medicalScenes
    case sadEndings
    case fastCutting
    case suspense
    case realisticViolence
    case strongLanguage
    case horror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loudNoises:        return "Loud Noises"
        case .jumpScares:        return "Jump Scares"
        case .darkness:          return "Darkness"
        case .animalInDanger:    return "Animal in Danger"
        case .parentSeparation:  return "Parent Separation"
        case .characterDeath:    return "Character Death"
        case .bullying:          return "Bullying"
        case .medicalScenes:     return "Medical Scenes"
        case .sadEndings:        return "Sad Endings"
        case .fastCutting:       return "Fast Cutting"
        case .suspense:          return "Suspense"
        case .realisticViolence: return "Realistic Violence"
        case .strongLanguage:    return "Strong Language"
        case .horror:            return "Horror"
        }
    }

    /// Lower-case form used inside sentences.
    var phrase: String {
        switch self {
        case .loudNoises:        return "loud noises"
        case .jumpScares:        return "jump scares"
        case .darkness:          return "darkness"
        case .animalInDanger:    return "an animal in danger"
        case .parentSeparation:  return "a parent separation"
        case .characterDeath:    return "a character death"
        case .bullying:          return "bullying"
        case .medicalScenes:     return "medical scenes"
        case .sadEndings:        return "a sad ending"
        case .fastCutting:       return "fast cutting"
        case .suspense:          return "suspense"
        case .realisticViolence: return "realistic violence"
        case .strongLanguage:    return "strong language"
        case .horror:            return "horror"
        }
    }

    /// The twelve a viewer can be marked sensitive to (spec §3).
    static let sensitivityOptions: [ContentAspect] = [
        .loudNoises, .jumpScares, .darkness, .animalInDanger,
        .parentSeparation, .characterDeath, .bullying, .medicalScenes,
        .sadEndings, .fastCutting, .suspense, .realisticViolence
    ]

    /// Everything that can be recorded about a title.
    static let contentOptions: [ContentAspect] = ContentAspect.allCases
}

// MARK: - Viewers

enum ViewerRole: String, Codable, CaseIterable, Identifiable {
    case child, teenager, adult
    var id: String { rawValue }
    var title: String {
        switch self {
        case .child: return "Child"
        case .teenager: return "Teenager"
        case .adult: return "Adult"
        }
    }
    var requiresAge: Bool { self == .child }
    var isGrownUp: Bool { self == .adult }
}

/// A sensitivity carries dates: children change, and the app has to show that.
struct SensitivityRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var aspect: ContentAspect
    var addedOn: Date
    var grownOutOn: Date?
    var note: String

    init(id: UUID = UUID(), aspect: ContentAspect, addedOn: Date = Date(), grownOutOn: Date? = nil, note: String = "") {
        self.id = id
        self.aspect = aspect
        self.addedOn = addedOn
        self.grownOutOn = grownOutOn
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        aspect = ContentAspect(rawValue: c.value(.aspect, ContentAspect.jumpScares.rawValue)) ?? .jumpScares
        addedOn = c.value(.addedOn, Date())
        grownOutOn = c.value(.grownOutOn, Date?.none)
        note = c.value(.note, "")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(aspect.rawValue, forKey: .aspect)
        try c.encode(addedOn, forKey: .addedOn)
        try c.encodeIfPresent(grownOutOn, forKey: .grownOutOn)
        try c.encode(note, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey { case id, aspect, addedOn, grownOutOn, note }

    var isActive: Bool { grownOutOn == nil }
}

struct Viewer: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var role: ViewerRole
    var age: Int?
    var colourIndex: Int
    var attentionSpanMinutes: Int
    var sensitivities: [SensitivityRecord]
    var loves: [String]
    var avoids: [String]
    var bedtimeOverride: TimeOfDay?
    var notes: String
    var weeklyLimitMinutes: Int?
    var rolloverAllowed: Bool
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         role: ViewerRole = .child,
         age: Int? = nil,
         colourIndex: Int = 0,
         attentionSpanMinutes: Int = 60,
         sensitivities: [SensitivityRecord] = [],
         loves: [String] = [],
         avoids: [String] = [],
         bedtimeOverride: TimeOfDay? = nil,
         notes: String = "",
         weeklyLimitMinutes: Int? = nil,
         rolloverAllowed: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.role = role
        self.age = age
        self.colourIndex = colourIndex
        self.attentionSpanMinutes = attentionSpanMinutes
        self.sensitivities = sensitivities
        self.loves = loves
        self.avoids = avoids
        self.bedtimeOverride = bedtimeOverride
        self.notes = notes
        self.weeklyLimitMinutes = weeklyLimitMinutes
        self.rolloverAllowed = rolloverAllowed
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        role = ViewerRole(rawValue: c.value(.role, ViewerRole.child.rawValue)) ?? .child
        age = c.value(.age, Int?.none)
        colourIndex = c.value(.colourIndex, 0)
        attentionSpanMinutes = max(5, c.value(.attentionSpanMinutes, 60))
        sensitivities = c.value(.sensitivities, [SensitivityRecord]())
        loves = c.value(.loves, [String]())
        avoids = c.value(.avoids, [String]())
        bedtimeOverride = c.value(.bedtimeOverride, TimeOfDay?.none)
        notes = c.value(.notes, "")
        weeklyLimitMinutes = c.value(.weeklyLimitMinutes, Int?.none)
        rolloverAllowed = c.value(.rolloverAllowed, false)
        createdAt = c.value(.createdAt, Date())
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(role.rawValue, forKey: .role)
        try c.encodeIfPresent(age, forKey: .age)
        try c.encode(colourIndex, forKey: .colourIndex)
        try c.encode(attentionSpanMinutes, forKey: .attentionSpanMinutes)
        try c.encode(sensitivities, forKey: .sensitivities)
        try c.encode(loves, forKey: .loves)
        try c.encode(avoids, forKey: .avoids)
        try c.encodeIfPresent(bedtimeOverride, forKey: .bedtimeOverride)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(weeklyLimitMinutes, forKey: .weeklyLimitMinutes)
        try c.encode(rolloverAllowed, forKey: .rolloverAllowed)
        try c.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, role, age, colourIndex, attentionSpanMinutes, sensitivities
        case loves, avoids, bedtimeOverride, notes, weeklyLimitMinutes, rolloverAllowed, createdAt
    }

    var activeSensitivities: [SensitivityRecord] { sensitivities.filter { $0.isActive } }
    var activeAspects: Set<ContentAspect> { Set(activeSensitivities.map(\.aspect)) }
    var retiredSensitivities: [SensitivityRecord] { sensitivities.filter { !$0.isActive } }

    var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// Third-person pronoun-free possessive used in generated sentences.
    var possessive: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "their" }
        return trimmed.hasSuffix("s") ? "\(trimmed)’" : "\(trimmed)’s"
    }
}

// MARK: - Titles

enum ContentType: String, Codable, CaseIterable, Identifiable {
    case film, series, documentary, animation, short
    var id: String { rawValue }
    var title: String {
        switch self {
        case .film: return "Film"
        case .series: return "Series"
        case .documentary: return "Documentary"
        case .animation: return "Animation"
        case .short: return "Short"
        }
    }
    var isEpisodic: Bool { self == .series }
}

enum GenreCatalogue {
    static let all: [String] = [
        "Adventure", "Animation", "Comedy", "Documentary", "Drama", "Family",
        "Fantasy", "History", "Musical", "Mystery", "Nature", "Science Fiction", "Sport"
    ]
}

struct Episode: Codable, Identifiable, Hashable {
    var id: UUID
    var number: Int
    var name: String
    var runtimeMinutes: Int

    init(id: UUID = UUID(), number: Int, name: String = "", runtimeMinutes: Int = 24) {
        self.id = id; self.number = number; self.name = name; self.runtimeMinutes = runtimeMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        number = c.value(.number, 1)
        name = c.value(.name, "")
        runtimeMinutes = max(1, c.value(.runtimeMinutes, 24))
    }
    private enum CodingKeys: String, CodingKey { case id, number, name, runtimeMinutes }
}

struct SeriesSeason: Codable, Identifiable, Hashable {
    var id: UUID
    var number: Int
    var name: String
    var episodes: [Episode]

    init(id: UUID = UUID(), number: Int, name: String = "", episodes: [Episode] = []) {
        self.id = id; self.number = number; self.name = name; self.episodes = episodes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        number = c.value(.number, 1)
        name = c.value(.name, "")
        episodes = c.value(.episodes, [Episode]())
    }
    private enum CodingKeys: String, CodingKey { case id, number, name, episodes }
}

/// Where the series is up to.
struct SeriesPosition: Codable, Hashable {
    var seasonNumber: Int
    var episodeNumber: Int
    var lastWatched: Date?

    init(seasonNumber: Int = 1, episodeNumber: Int = 0, lastWatched: Date? = nil) {
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.lastWatched = lastWatched
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seasonNumber = c.value(.seasonNumber, 1)
        episodeNumber = c.value(.episodeNumber, 0)
        lastWatched = c.value(.lastWatched, Date?.none)
    }
    private enum CodingKeys: String, CodingKey { case seasonNumber, episodeNumber, lastWatched }
}

struct Title: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var originalName: String
    var type: ContentType
    var runtimeMinutes: Int
    var genres: [String]
    var releaseYear: Int?
    /// Certification code keyed by `RatingCountry.rawValue`.
    var certifications: [String: String]
    var shortDescription: String
    var whereToWatch: String
    var posterFileName: String?
    var contentAspects: [ContentAspect]
    var contentNotesText: String
    var personalTags: [String]
    var privateNote: String
    var isFavourite: Bool
    var isArchived: Bool
    var tmdbId: Int?
    /// Field names the parent has edited by hand — never overwritten by a refresh.
    var editedFields: [String]
    var seasons: [SeriesSeason]
    var seriesPosition: SeriesPosition?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String = "",
         originalName: String = "",
         type: ContentType = .film,
         runtimeMinutes: Int = 0,
         genres: [String] = [],
         releaseYear: Int? = nil,
         certifications: [String: String] = [:],
         shortDescription: String = "",
         whereToWatch: String = "",
         posterFileName: String? = nil,
         contentAspects: [ContentAspect] = [],
         contentNotesText: String = "",
         personalTags: [String] = [],
         privateNote: String = "",
         isFavourite: Bool = false,
         isArchived: Bool = false,
         tmdbId: Int? = nil,
         editedFields: [String] = [],
         seasons: [SeriesSeason] = [],
         seriesPosition: SeriesPosition? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.type = type
        self.runtimeMinutes = runtimeMinutes
        self.genres = genres
        self.releaseYear = releaseYear
        self.certifications = certifications
        self.shortDescription = shortDescription
        self.whereToWatch = whereToWatch
        self.posterFileName = posterFileName
        self.contentAspects = contentAspects
        self.contentNotesText = contentNotesText
        self.personalTags = personalTags
        self.privateNote = privateNote
        self.isFavourite = isFavourite
        self.isArchived = isArchived
        self.tmdbId = tmdbId
        self.editedFields = editedFields
        self.seasons = seasons
        self.seriesPosition = seriesPosition
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        originalName = c.value(.originalName, "")
        type = ContentType(rawValue: c.value(.type, ContentType.film.rawValue)) ?? .film
        runtimeMinutes = max(0, c.value(.runtimeMinutes, 0))
        genres = c.value(.genres, [String]())
        releaseYear = c.value(.releaseYear, Int?.none)
        certifications = c.value(.certifications, [String: String]())
        shortDescription = c.value(.shortDescription, "")
        whereToWatch = c.value(.whereToWatch, "")
        posterFileName = c.value(.posterFileName, String?.none)
        contentAspects = c.value(.contentAspects, [String]()).compactMap { ContentAspect(rawValue: $0) }
        contentNotesText = c.value(.contentNotesText, "")
        personalTags = c.value(.personalTags, [String]())
        privateNote = c.value(.privateNote, "")
        isFavourite = c.value(.isFavourite, false)
        isArchived = c.value(.isArchived, false)
        tmdbId = c.value(.tmdbId, Int?.none)
        editedFields = c.value(.editedFields, [String]())
        seasons = c.value(.seasons, [SeriesSeason]())
        seriesPosition = c.value(.seriesPosition, SeriesPosition?.none)
        createdAt = c.value(.createdAt, Date())
        updatedAt = c.value(.updatedAt, Date())
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(originalName, forKey: .originalName)
        try c.encode(type.rawValue, forKey: .type)
        try c.encode(runtimeMinutes, forKey: .runtimeMinutes)
        try c.encode(genres, forKey: .genres)
        try c.encodeIfPresent(releaseYear, forKey: .releaseYear)
        try c.encode(certifications, forKey: .certifications)
        try c.encode(shortDescription, forKey: .shortDescription)
        try c.encode(whereToWatch, forKey: .whereToWatch)
        try c.encodeIfPresent(posterFileName, forKey: .posterFileName)
        try c.encode(contentAspects.map(\.rawValue), forKey: .contentAspects)
        try c.encode(contentNotesText, forKey: .contentNotesText)
        try c.encode(personalTags, forKey: .personalTags)
        try c.encode(privateNote, forKey: .privateNote)
        try c.encode(isFavourite, forKey: .isFavourite)
        try c.encode(isArchived, forKey: .isArchived)
        try c.encodeIfPresent(tmdbId, forKey: .tmdbId)
        try c.encode(editedFields, forKey: .editedFields)
        try c.encode(seasons, forKey: .seasons)
        try c.encodeIfPresent(seriesPosition, forKey: .seriesPosition)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, originalName, type, runtimeMinutes, genres, releaseYear, certifications
        case shortDescription, whereToWatch, posterFileName, contentAspects, contentNotesText
        case personalTags, privateNote, isFavourite, isArchived, tmdbId, editedFields
        case seasons, seriesPosition, createdAt, updatedAt
    }

    func certification(for country: RatingCountry) -> String? {
        let code = certifications[country.rawValue]
        return (code?.isEmpty ?? true) ? nil : code
    }

    /// True when we genuinely know nothing about what is in it.
    var hasContentDetail: Bool {
        !contentAspects.isEmpty || !contentNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var yearText: String { releaseYear.map(String.init) ?? "—" }

    var episodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.count } }

    func episode(season: Int, number: Int) -> Episode? {
        seasons.first { $0.number == season }?.episodes.first { $0.number == number }
    }

    /// Next unwatched episode given the stored position.
    var nextEpisode: (season: Int, episode: Episode)? {
        guard type.isEpisodic else { return nil }
        let pos = seriesPosition ?? SeriesPosition()
        let ordered = seasons.sorted { $0.number < $1.number }
        for season in ordered {
            let eps = season.episodes.sorted { $0.number < $1.number }
            for ep in eps {
                if season.number > pos.seasonNumber ||
                    (season.number == pos.seasonNumber && ep.number > pos.episodeNumber) {
                    return (season.number, ep)
                }
            }
        }
        return nil
    }

    var episodesLeft: Int {
        guard type.isEpisodic else { return 0 }
        let pos = seriesPosition ?? SeriesPosition()
        return seasons.reduce(0) { partial, season in
            partial + season.episodes.filter {
                season.number > pos.seasonNumber ||
                (season.number == pos.seasonNumber && $0.number > pos.episodeNumber)
            }.count
        }
    }
}

/// Frozen copy kept on a completed evening, so deleting a title never destroys history.
struct TitleSnapshot: Codable, Hashable {
    var name: String
    var runtimeMinutes: Int
    var certificationCode: String?
    var certificationCountry: String?
    var type: ContentType
    var genres: [String]

    init(name: String = "", runtimeMinutes: Int = 0, certificationCode: String? = nil,
         certificationCountry: String? = nil, type: ContentType = .film, genres: [String] = []) {
        self.name = name
        self.runtimeMinutes = runtimeMinutes
        self.certificationCode = certificationCode
        self.certificationCountry = certificationCountry
        self.type = type
        self.genres = genres
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "")
        runtimeMinutes = c.value(.runtimeMinutes, 0)
        certificationCode = c.value(.certificationCode, String?.none)
        certificationCountry = c.value(.certificationCountry, String?.none)
        type = ContentType(rawValue: c.value(.type, ContentType.film.rawValue)) ?? .film
        genres = c.value(.genres, [String]())
    }

    private enum CodingKeys: String, CodingKey {
        case name, runtimeMinutes, certificationCode, certificationCountry, type, genres
    }

    init(title: Title, country: RatingCountry) {
        self.name = title.name
        self.runtimeMinutes = title.runtimeMinutes
        self.certificationCode = title.certification(for: country)
        self.certificationCountry = country.rawValue
        self.type = title.type
        self.genres = title.genres
    }
}

// MARK: - House rules

enum RuleType: String, Codable, CaseIterable, Identifiable {
    case maxCertificationPerAge
    case noStrongLanguage
    case noRealisticViolence
    case noHorror
    case subtitlesOnlyAboveAge
    case maxRuntimeOnWeeknights
    case oneFilmPerEvening
    case noScreensAfterTime
    case parentMustWatchTogether

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maxCertificationPerAge:  return "Maximum Certification per Age"
        case .noStrongLanguage:        return "No Strong Language"
        case .noRealisticViolence:     return "No Realistic Violence"
        case .noHorror:                return "No Horror"
        case .subtitlesOnlyAboveAge:   return "Subtitles Only Above Age"
        case .maxRuntimeOnWeeknights:  return "Maximum Runtime on Weeknights"
        case .oneFilmPerEvening:       return "One Film per Evening"
        case .noScreensAfterTime:      return "No Screens After Time"
        case .parentMustWatchTogether: return "Parent Must Watch Together"
        }
    }

    var explanation: String {
        switch self {
        case .maxCertificationPerAge:  return "Under a given age, nothing above a chosen certificate."
        case .noStrongLanguage:        return "Titles marked with strong language are flagged."
        case .noRealisticViolence:     return "Titles marked with realistic violence are flagged."
        case .noHorror:                return "Titles marked as horror are flagged."
        case .subtitlesOnlyAboveAge:   return "Subtitled titles only once a viewer is old enough to read them."
        case .maxRuntimeOnWeeknights:  return "A ceiling on running time from Sunday to Thursday."
        case .oneFilmPerEvening:       return "One title per evening, however short."
        case .noScreensAfterTime:      return "Nothing starts, or runs, past a set time."
        case .parentMustWatchTogether: return "An adult has to be in the room."
        }
    }

    var needsAge: Bool { self == .maxCertificationPerAge || self == .subtitlesOnlyAboveAge }
    var needsCertification: Bool { self == .maxCertificationPerAge }
    var needsMinutes: Bool { self == .maxRuntimeOnWeeknights }
    var needsTime: Bool { self == .noScreensAfterTime }

    /// A rule about the clock or the calendar reads "Not Tonight";
    /// a rule about content or age reads "Not Yet".
    var isTimeBased: Bool {
        self == .maxRuntimeOnWeeknights || self == .noScreensAfterTime || self == .oneFilmPerEvening
    }
}

struct HouseRule: Codable, Identifiable, Hashable {
    var id: UUID
    var type: RuleType
    var age: Int?
    var certificationCode: String?
    var minutes: Int?
    var time: TimeOfDay?
    /// Empty means everyone in the house.
    var appliesTo: [UUID]
    var exceptionAllowed: Bool
    var notes: String
    var isActive: Bool
    var createdAt: Date
    var retiredAt: Date?

    init(id: UUID = UUID(),
         type: RuleType,
         age: Int? = nil,
         certificationCode: String? = nil,
         minutes: Int? = nil,
         time: TimeOfDay? = nil,
         appliesTo: [UUID] = [],
         exceptionAllowed: Bool = true,
         notes: String = "",
         isActive: Bool = true,
         createdAt: Date = Date(),
         retiredAt: Date? = nil) {
        self.id = id
        self.type = type
        self.age = age
        self.certificationCode = certificationCode
        self.minutes = minutes
        self.time = time
        self.appliesTo = appliesTo
        self.exceptionAllowed = exceptionAllowed
        self.notes = notes
        self.isActive = isActive
        self.createdAt = createdAt
        self.retiredAt = retiredAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        type = RuleType(rawValue: c.value(.type, RuleType.noHorror.rawValue)) ?? .noHorror
        age = c.value(.age, Int?.none)
        certificationCode = c.value(.certificationCode, String?.none)
        minutes = c.value(.minutes, Int?.none)
        time = c.value(.time, TimeOfDay?.none)
        appliesTo = c.value(.appliesTo, [UUID]())
        exceptionAllowed = c.value(.exceptionAllowed, true)
        notes = c.value(.notes, "")
        isActive = c.value(.isActive, true)
        createdAt = c.value(.createdAt, Date())
        retiredAt = c.value(.retiredAt, Date?.none)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type.rawValue, forKey: .type)
        try c.encodeIfPresent(age, forKey: .age)
        try c.encodeIfPresent(certificationCode, forKey: .certificationCode)
        try c.encodeIfPresent(minutes, forKey: .minutes)
        try c.encodeIfPresent(time, forKey: .time)
        try c.encode(appliesTo, forKey: .appliesTo)
        try c.encode(exceptionAllowed, forKey: .exceptionAllowed)
        try c.encode(notes, forKey: .notes)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(retiredAt, forKey: .retiredAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, age, certificationCode, minutes, time, appliesTo
        case exceptionAllowed, notes, isActive, createdAt, retiredAt
    }

    var valueSummary: String {
        switch type {
        case .maxCertificationPerAge:
            let cert = certificationCode ?? "—"
            return "Under \(age ?? 0): nothing above \(cert)"
        case .subtitlesOnlyAboveAge:
            return "Subtitles only from age \(age ?? 0)"
        case .maxRuntimeOnWeeknights:
            return "\(minutes ?? 0) minutes on weeknights"
        case .noScreensAfterTime:
            return "Nothing after \(time?.display ?? "—")"
        case .oneFilmPerEvening:
            return "One title per evening"
        default:
            return type.explanation
        }
    }

    func applies(to viewer: Viewer) -> Bool {
        appliesTo.isEmpty || appliesTo.contains(viewer.id)
    }
}

struct RuleHistoryEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var ruleId: UUID
    var ruleTitle: String
    var change: String
    var date: Date

    init(id: UUID = UUID(), ruleId: UUID, ruleTitle: String, change: String, date: Date = Date()) {
        self.id = id; self.ruleId = ruleId; self.ruleTitle = ruleTitle; self.change = change; self.date = date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        ruleId = c.value(.ruleId, UUID())
        ruleTitle = c.value(.ruleTitle, "")
        change = c.value(.change, "")
        date = c.value(.date, Date())
    }
    private enum CodingKeys: String, CodingKey { case id, ruleId, ruleTitle, change, date }
}

struct RuleException: Codable, Identifiable, Hashable {
    var id: UUID
    var ruleId: UUID
    var ruleTitle: String
    var reason: String
    var date: Date

    init(id: UUID = UUID(), ruleId: UUID, ruleTitle: String, reason: String, date: Date = Date()) {
        self.id = id; self.ruleId = ruleId; self.ruleTitle = ruleTitle; self.reason = reason; self.date = date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        ruleId = c.value(.ruleId, UUID())
        ruleTitle = c.value(.ruleTitle, "")
        reason = c.value(.reason, "")
        date = c.value(.date, Date())
    }
    private enum CodingKeys: String, CodingKey { case id, ruleId, ruleTitle, reason, date }
}

// MARK: - Evenings

enum Occasion: String, Codable, CaseIterable, Identifiable {
    case regular, weekend, sickDay, sleepover, holiday, specialTreat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: return "Regular Evening"
        case .weekend: return "Weekend"
        case .sickDay: return "Sick Day"
        case .sleepover: return "Sleepover"
        case .holiday: return "Holiday"
        case .specialTreat: return "Special Treat"
        }
    }
}

enum EveningState: String, Codable {
    case draft, planned, watching, awaitingReactions, completed
    var title: String {
        switch self {
        case .draft: return "Draft"
        case .planned: return "Planned"
        case .watching: return "In Progress"
        case .awaitingReactions: return "Waiting for Reactions"
        case .completed: return "Completed"
        }
    }
}

enum EveningOutcome: String, Codable, CaseIterable, Identifiable {
    case finished, stoppedEarly, splitAcrossEvenings, replacedMidEvening
    var id: String { rawValue }
    var title: String {
        switch self {
        case .finished: return "Finished"
        case .stoppedEarly: return "Stopped Early"
        case .splitAcrossEvenings: return "Split Across Evenings"
        case .replacedMidEvening: return "Replaced Mid-Evening"
        }
    }
}

enum StopReason: String, Codable, CaseIterable, Identifiable {
    case tooScary, tooLong, lostInterest, bedtime, somethingCameUp, technicalProblem
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tooScary: return "Too Scary"
        case .tooLong: return "Too Long"
        case .lostInterest: return "Lost Interest"
        case .bedtime: return "Bedtime"
        case .somethingCameUp: return "Something Came Up"
        case .technicalProblem: return "Technical Problem"
        }
    }
}

enum MomentKind: String, Codable, CaseIterable, Identifiable {
    case scary, sad, loud, boring, funny, confusing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scary: return "Scary"
        case .sad: return "Sad"
        case .loud: return "Loud"
        case .boring: return "Boring"
        case .funny: return "Funny"
        case .confusing: return "Confusing"
        }
    }
    /// Marks that are worth surfacing before the next watch.
    var isCautionary: Bool { self == .scary || self == .sad || self == .loud }
}

struct MarkedMoment: Codable, Identifiable, Hashable {
    var id: UUID
    var atSeconds: Int
    var kind: MomentKind
    var note: String

    init(id: UUID = UUID(), atSeconds: Int, kind: MomentKind, note: String = "") {
        self.id = id; self.atSeconds = atSeconds; self.kind = kind; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        atSeconds = c.value(.atSeconds, 0)
        kind = MomentKind(rawValue: c.value(.kind, MomentKind.scary.rawValue)) ?? .scary
        note = c.value(.note, "")
    }
    private enum CodingKeys: String, CodingKey { case id, atSeconds, kind, note }

    var timecode: String { TimeFormat.clock(seconds: atSeconds) }
}

enum Impression: String, Codable, CaseIterable, Identifiable {
    case notForThem, okay, good, great, lovedIt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notForThem: return "Not for Them"
        case .okay: return "Okay"
        case .good: return "Good"
        case .great: return "Great"
        case .lovedIt: return "Loved It"
        }
    }
    /// 1…5, used only for aggregation in Insights — never shown as a score.
    var weight: Int {
        switch self {
        case .notForThem: return 1
        case .okay: return 2
        case .good: return 3
        case .great: return 4
        case .lovedIt: return 5
        }
    }
}

struct Reaction: Codable, Identifiable, Hashable {
    var id: UUID
    var viewerId: UUID
    var impression: Impression?
    var watchedToEnd: Bool
    var gotScared: Bool
    var askedQuestions: Bool
    var fellAsleep: Bool
    var wantsAgain: Bool
    var bestMoment: String
    var privateNote: String

    init(id: UUID = UUID(), viewerId: UUID, impression: Impression? = nil,
         watchedToEnd: Bool = false, gotScared: Bool = false, askedQuestions: Bool = false,
         fellAsleep: Bool = false, wantsAgain: Bool = false,
         bestMoment: String = "", privateNote: String = "") {
        self.id = id
        self.viewerId = viewerId
        self.impression = impression
        self.watchedToEnd = watchedToEnd
        self.gotScared = gotScared
        self.askedQuestions = askedQuestions
        self.fellAsleep = fellAsleep
        self.wantsAgain = wantsAgain
        self.bestMoment = bestMoment
        self.privateNote = privateNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        viewerId = c.value(.viewerId, UUID())
        if let raw = c.value(.impression, String?.none) { impression = Impression(rawValue: raw) } else { impression = nil }
        watchedToEnd = c.value(.watchedToEnd, false)
        gotScared = c.value(.gotScared, false)
        askedQuestions = c.value(.askedQuestions, false)
        fellAsleep = c.value(.fellAsleep, false)
        wantsAgain = c.value(.wantsAgain, false)
        bestMoment = c.value(.bestMoment, "")
        privateNote = c.value(.privateNote, "")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(viewerId, forKey: .viewerId)
        try c.encodeIfPresent(impression?.rawValue, forKey: .impression)
        try c.encode(watchedToEnd, forKey: .watchedToEnd)
        try c.encode(gotScared, forKey: .gotScared)
        try c.encode(askedQuestions, forKey: .askedQuestions)
        try c.encode(fellAsleep, forKey: .fellAsleep)
        try c.encode(wantsAgain, forKey: .wantsAgain)
        try c.encode(bestMoment, forKey: .bestMoment)
        try c.encode(privateNote, forKey: .privateNote)
    }

    private enum CodingKeys: String, CodingKey {
        case id, viewerId, impression, watchedToEnd, gotScared, askedQuestions
        case fellAsleep, wantsAgain, bestMoment, privateNote
    }

    var isEmpty: Bool {
        impression == nil && !watchedToEnd && !gotScared && !askedQuestions
            && !fellAsleep && !wantsAgain
            && bestMoment.trimmingCharacters(in: .whitespaces).isEmpty
            && privateNote.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Everything about the evening's clock, exactly as spec §7 states it.
struct WindowSetup: Codable, Hashable {
    var bedtime: TimeOfDay
    var settlingMinutes: Int
    var pauseCount: Int
    var pauseLengthMinutes: Int
    var snackBreakMinutes: Int
    var bufferMinutes: Int

    init(bedtime: TimeOfDay = .defaultWeeknight,
         settlingMinutes: Int = 20,
         pauseCount: Int = 1,
         pauseLengthMinutes: Int = 10,
         snackBreakMinutes: Int = 0,
         bufferMinutes: Int = 5) {
        self.bedtime = bedtime
        self.settlingMinutes = max(0, settlingMinutes)
        self.pauseCount = max(0, pauseCount)
        self.pauseLengthMinutes = max(0, pauseLengthMinutes)
        self.snackBreakMinutes = max(0, snackBreakMinutes)
        self.bufferMinutes = max(0, bufferMinutes)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bedtime = c.value(.bedtime, TimeOfDay.defaultWeeknight)
        settlingMinutes = max(0, c.value(.settlingMinutes, 20))
        pauseCount = max(0, c.value(.pauseCount, 1))
        pauseLengthMinutes = max(0, c.value(.pauseLengthMinutes, 10))
        snackBreakMinutes = max(0, c.value(.snackBreakMinutes, 0))
        bufferMinutes = max(0, c.value(.bufferMinutes, 5))
    }

    private enum CodingKeys: String, CodingKey {
        case bedtime, settlingMinutes, pauseCount, pauseLengthMinutes, snackBreakMinutes, bufferMinutes
    }

    /// Everything around the film itself.
    var overheadMinutes: Int {
        settlingMinutes + (pauseCount * pauseLengthMinutes) + snackBreakMinutes + bufferMinutes
    }
}

struct WatchSession: Codable, Hashable {
    var startedAt: Date?
    var accumulatedSeconds: Int
    var isPaused: Bool
    var lastResumedAt: Date?
    var marks: [MarkedMoment]
    var stopReason: StopReason?
    var stoppedAtSeconds: Int?
    /// Where a split evening picks up from.
    var resumeFromSeconds: Int

    init(startedAt: Date? = nil, accumulatedSeconds: Int = 0, isPaused: Bool = false,
         lastResumedAt: Date? = nil, marks: [MarkedMoment] = [],
         stopReason: StopReason? = nil, stoppedAtSeconds: Int? = nil, resumeFromSeconds: Int = 0) {
        self.startedAt = startedAt
        self.accumulatedSeconds = accumulatedSeconds
        self.isPaused = isPaused
        self.lastResumedAt = lastResumedAt
        self.marks = marks
        self.stopReason = stopReason
        self.stoppedAtSeconds = stoppedAtSeconds
        self.resumeFromSeconds = resumeFromSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = c.value(.startedAt, Date?.none)
        accumulatedSeconds = max(0, c.value(.accumulatedSeconds, 0))
        isPaused = c.value(.isPaused, false)
        lastResumedAt = c.value(.lastResumedAt, Date?.none)
        marks = c.value(.marks, [MarkedMoment]())
        if let raw = c.value(.stopReason, String?.none) { stopReason = StopReason(rawValue: raw) } else { stopReason = nil }
        stoppedAtSeconds = c.value(.stoppedAtSeconds, Int?.none)
        resumeFromSeconds = max(0, c.value(.resumeFromSeconds, 0))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encode(accumulatedSeconds, forKey: .accumulatedSeconds)
        try c.encode(isPaused, forKey: .isPaused)
        try c.encodeIfPresent(lastResumedAt, forKey: .lastResumedAt)
        try c.encode(marks, forKey: .marks)
        try c.encodeIfPresent(stopReason?.rawValue, forKey: .stopReason)
        try c.encodeIfPresent(stoppedAtSeconds, forKey: .stoppedAtSeconds)
        try c.encode(resumeFromSeconds, forKey: .resumeFromSeconds)
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt, accumulatedSeconds, isPaused, lastResumedAt, marks
        case stopReason, stoppedAtSeconds, resumeFromSeconds
    }

    /// Elapsed seconds as of `now`, honouring the paused state. The timer is a
    /// display over stored anchors, never the source of truth.
    func elapsed(at now: Date = Date()) -> Int {
        guard let resumed = lastResumedAt, !isPaused else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, Int(now.timeIntervalSince(resumed)))
    }

    var isRunning: Bool { startedAt != nil && !isPaused }
}

struct EpisodeRef: Codable, Hashable {
    var seasonNumber: Int
    var episodeNumber: Int
    var name: String
    var runtimeMinutes: Int

    init(seasonNumber: Int, episodeNumber: Int, name: String = "", runtimeMinutes: Int = 0) {
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.name = name
        self.runtimeMinutes = runtimeMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seasonNumber = c.value(.seasonNumber, 1)
        episodeNumber = c.value(.episodeNumber, 1)
        name = c.value(.name, "")
        runtimeMinutes = c.value(.runtimeMinutes, 0)
    }
    private enum CodingKeys: String, CodingKey { case seasonNumber, episodeNumber, name, runtimeMinutes }

    var label: String { "S\(seasonNumber) · E\(episodeNumber)" }
}

struct Evening: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var date: Date
    var startTime: TimeOfDay
    var occasion: Occasion
    var viewerIds: [UUID]
    var window: WindowSetup
    var titleId: UUID?
    var titleSnapshot: TitleSnapshot?
    var episodeRef: EpisodeRef?
    var exceptions: [RuleException]
    var state: EveningState
    var outcome: EveningOutcome?
    var watch: WatchSession
    var reactions: [Reaction]
    var parentNote: String
    /// Set when the wizard opens; powers the "Time to Choose a Film" insight.
    var planningStartedAt: Date?
    var continuedFromEveningId: UUID?
    var createdAt: Date
    var completedAt: Date?

    init(id: UUID = UUID(),
         name: String = "",
         date: Date = Date(),
         startTime: TimeOfDay = TimeOfDay(hour: 18, minute: 40),
         occasion: Occasion = .regular,
         viewerIds: [UUID] = [],
         window: WindowSetup = WindowSetup(),
         titleId: UUID? = nil,
         titleSnapshot: TitleSnapshot? = nil,
         episodeRef: EpisodeRef? = nil,
         exceptions: [RuleException] = [],
         state: EveningState = .draft,
         outcome: EveningOutcome? = nil,
         watch: WatchSession = WatchSession(),
         reactions: [Reaction] = [],
         parentNote: String = "",
         planningStartedAt: Date? = nil,
         continuedFromEveningId: UUID? = nil,
         createdAt: Date = Date(),
         completedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.startTime = startTime
        self.occasion = occasion
        self.viewerIds = viewerIds
        self.window = window
        self.titleId = titleId
        self.titleSnapshot = titleSnapshot
        self.episodeRef = episodeRef
        self.exceptions = exceptions
        self.state = state
        self.outcome = outcome
        self.watch = watch
        self.reactions = reactions
        self.parentNote = parentNote
        self.planningStartedAt = planningStartedAt
        self.continuedFromEveningId = continuedFromEveningId
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        date = c.value(.date, Date())
        startTime = c.value(.startTime, TimeOfDay(hour: 18, minute: 40))
        occasion = Occasion(rawValue: c.value(.occasion, Occasion.regular.rawValue)) ?? .regular
        viewerIds = c.value(.viewerIds, [UUID]())
        window = c.value(.window, WindowSetup())
        titleId = c.value(.titleId, UUID?.none)
        titleSnapshot = c.value(.titleSnapshot, TitleSnapshot?.none)
        episodeRef = c.value(.episodeRef, EpisodeRef?.none)
        exceptions = c.value(.exceptions, [RuleException]())
        state = EveningState(rawValue: c.value(.state, EveningState.draft.rawValue)) ?? .draft
        if let raw = c.value(.outcome, String?.none) { outcome = EveningOutcome(rawValue: raw) } else { outcome = nil }
        watch = c.value(.watch, WatchSession())
        reactions = c.value(.reactions, [Reaction]())
        parentNote = c.value(.parentNote, "")
        planningStartedAt = c.value(.planningStartedAt, Date?.none)
        continuedFromEveningId = c.value(.continuedFromEveningId, UUID?.none)
        createdAt = c.value(.createdAt, Date())
        completedAt = c.value(.completedAt, Date?.none)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(date, forKey: .date)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(occasion.rawValue, forKey: .occasion)
        try c.encode(viewerIds, forKey: .viewerIds)
        try c.encode(window, forKey: .window)
        try c.encodeIfPresent(titleId, forKey: .titleId)
        try c.encodeIfPresent(titleSnapshot, forKey: .titleSnapshot)
        try c.encodeIfPresent(episodeRef, forKey: .episodeRef)
        try c.encode(exceptions, forKey: .exceptions)
        try c.encode(state.rawValue, forKey: .state)
        try c.encodeIfPresent(outcome?.rawValue, forKey: .outcome)
        try c.encode(watch, forKey: .watch)
        try c.encode(reactions, forKey: .reactions)
        try c.encode(parentNote, forKey: .parentNote)
        try c.encodeIfPresent(planningStartedAt, forKey: .planningStartedAt)
        try c.encodeIfPresent(continuedFromEveningId, forKey: .continuedFromEveningId)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, date, startTime, occasion, viewerIds, window, titleId, titleSnapshot
        case episodeRef, exceptions, state, outcome, watch, reactions, parentNote
        case planningStartedAt, continuedFromEveningId, createdAt, completedAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (titleSnapshot?.name ?? "Untitled Evening") : trimmed
    }

    /// The running time this evening is actually planning for.
    var plannedRuntimeMinutes: Int {
        episodeRef?.runtimeMinutes ?? titleSnapshot?.runtimeMinutes ?? 0
    }

    var watchedMinutes: Int {
        max(0, watch.elapsed()) / 60
    }

    var isUnfinished: Bool {
        state == .watching || (state == .planned && watch.startedAt != nil)
    }

    var needsReactions: Bool {
        state == .awaitingReactions || (state == .completed && reactions.allSatisfy { $0.impression == nil })
    }
}

// MARK: - Content notes

enum NoteSeverity: String, Codable, CaseIterable, Identifiable {
    case mild, notable, strong
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mild: return "Mild"
        case .notable: return "Notable"
        case .strong: return "Strong"
        }
    }
}

struct ContentNote: Codable, Identifiable, Hashable {
    var id: UUID
    var titleId: UUID
    var titleName: String
    var timestampSeconds: Int?
    var whatHappens: String
    var whoReacted: [UUID]
    var severity: NoteSeverity
    var adviceNextTime: String
    var warnBeforeWatching: Bool
    var createdAt: Date

    init(id: UUID = UUID(), titleId: UUID, titleName: String = "", timestampSeconds: Int? = nil,
         whatHappens: String = "", whoReacted: [UUID] = [], severity: NoteSeverity = .notable,
         adviceNextTime: String = "", warnBeforeWatching: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.titleId = titleId
        self.titleName = titleName
        self.timestampSeconds = timestampSeconds
        self.whatHappens = whatHappens
        self.whoReacted = whoReacted
        self.severity = severity
        self.adviceNextTime = adviceNextTime
        self.warnBeforeWatching = warnBeforeWatching
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        titleId = c.value(.titleId, UUID())
        titleName = c.value(.titleName, "")
        timestampSeconds = c.value(.timestampSeconds, Int?.none)
        whatHappens = c.value(.whatHappens, "")
        whoReacted = c.value(.whoReacted, [UUID]())
        severity = NoteSeverity(rawValue: c.value(.severity, NoteSeverity.notable.rawValue)) ?? .notable
        adviceNextTime = c.value(.adviceNextTime, "")
        warnBeforeWatching = c.value(.warnBeforeWatching, true)
        createdAt = c.value(.createdAt, Date())
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(titleId, forKey: .titleId)
        try c.encode(titleName, forKey: .titleName)
        try c.encodeIfPresent(timestampSeconds, forKey: .timestampSeconds)
        try c.encode(whatHappens, forKey: .whatHappens)
        try c.encode(whoReacted, forKey: .whoReacted)
        try c.encode(severity.rawValue, forKey: .severity)
        try c.encode(adviceNextTime, forKey: .adviceNextTime)
        try c.encode(warnBeforeWatching, forKey: .warnBeforeWatching)
        try c.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, titleId, titleName, timestampSeconds, whatHappens, whoReacted
        case severity, adviceNextTime, warnBeforeWatching, createdAt
    }

    var timecode: String? {
        timestampSeconds.map { TimeFormat.clock(seconds: $0) }
    }
}

// MARK: - Screen time

struct ScreenTimeException: Codable, Identifiable, Hashable {
    var id: UUID
    var viewerId: UUID
    var weekStart: Date
    var extraMinutes: Int
    var reason: String
    var createdAt: Date

    init(id: UUID = UUID(), viewerId: UUID, weekStart: Date, extraMinutes: Int,
         reason: String = "", createdAt: Date = Date()) {
        self.id = id
        self.viewerId = viewerId
        self.weekStart = weekStart
        self.extraMinutes = extraMinutes
        self.reason = reason
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        viewerId = c.value(.viewerId, UUID())
        weekStart = c.value(.weekStart, Date())
        extraMinutes = c.value(.extraMinutes, 0)
        reason = c.value(.reason, "")
        createdAt = c.value(.createdAt, Date())
    }
    private enum CodingKeys: String, CodingKey { case id, viewerId, weekStart, extraMinutes, reason, createdAt }
}

// MARK: - House profile

struct HouseProfile: Codable, Hashable {
    var displayName: String
    var ratingCountry: RatingCountry
    var weeknightBedtime: TimeOfDay
    var weekendBedtime: TimeOfDay
    var defaultWeeklyLimitMinutes: Int
    var defaultSettlingMinutes: Int
    var defaultPauseCount: Int
    var defaultPauseLengthMinutes: Int
    var defaultSnackBreakMinutes: Int
    var defaultBufferMinutes: Int
    var setupCompleted: Bool

    init(displayName: String = "",
         ratingCountry: RatingCountry = .gb,
         weeknightBedtime: TimeOfDay = .defaultWeeknight,
         weekendBedtime: TimeOfDay = .defaultWeekend,
         defaultWeeklyLimitMinutes: Int = 420,
         defaultSettlingMinutes: Int = 20,
         defaultPauseCount: Int = 1,
         defaultPauseLengthMinutes: Int = 10,
         defaultSnackBreakMinutes: Int = 0,
         defaultBufferMinutes: Int = 5,
         setupCompleted: Bool = false) {
        self.displayName = displayName
        self.ratingCountry = ratingCountry
        self.weeknightBedtime = weeknightBedtime
        self.weekendBedtime = weekendBedtime
        self.defaultWeeklyLimitMinutes = defaultWeeklyLimitMinutes
        self.defaultSettlingMinutes = defaultSettlingMinutes
        self.defaultPauseCount = defaultPauseCount
        self.defaultPauseLengthMinutes = defaultPauseLengthMinutes
        self.defaultSnackBreakMinutes = defaultSnackBreakMinutes
        self.defaultBufferMinutes = defaultBufferMinutes
        self.setupCompleted = setupCompleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = c.value(.displayName, "")
        ratingCountry = RatingCountry(rawValue: c.value(.ratingCountry, RatingCountry.gb.rawValue)) ?? .gb
        weeknightBedtime = c.value(.weeknightBedtime, TimeOfDay.defaultWeeknight)
        weekendBedtime = c.value(.weekendBedtime, TimeOfDay.defaultWeekend)
        defaultWeeklyLimitMinutes = c.value(.defaultWeeklyLimitMinutes, 420)
        defaultSettlingMinutes = c.value(.defaultSettlingMinutes, 20)
        defaultPauseCount = c.value(.defaultPauseCount, 1)
        defaultPauseLengthMinutes = c.value(.defaultPauseLengthMinutes, 10)
        defaultSnackBreakMinutes = c.value(.defaultSnackBreakMinutes, 0)
        defaultBufferMinutes = c.value(.defaultBufferMinutes, 5)
        setupCompleted = c.value(.setupCompleted, false)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(ratingCountry.rawValue, forKey: .ratingCountry)
        try c.encode(weeknightBedtime, forKey: .weeknightBedtime)
        try c.encode(weekendBedtime, forKey: .weekendBedtime)
        try c.encode(defaultWeeklyLimitMinutes, forKey: .defaultWeeklyLimitMinutes)
        try c.encode(defaultSettlingMinutes, forKey: .defaultSettlingMinutes)
        try c.encode(defaultPauseCount, forKey: .defaultPauseCount)
        try c.encode(defaultPauseLengthMinutes, forKey: .defaultPauseLengthMinutes)
        try c.encode(defaultSnackBreakMinutes, forKey: .defaultSnackBreakMinutes)
        try c.encode(defaultBufferMinutes, forKey: .defaultBufferMinutes)
        try c.encode(setupCompleted, forKey: .setupCompleted)
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, ratingCountry, weeknightBedtime, weekendBedtime
        case defaultWeeklyLimitMinutes, defaultSettlingMinutes, defaultPauseCount
        case defaultPauseLengthMinutes, defaultSnackBreakMinutes, defaultBufferMinutes, setupCompleted
    }

    func bedtime(on date: Date, calendar: Calendar = .current) -> TimeOfDay {
        calendar.isDateInWeekend(date) ? weekendBedtime : weeknightBedtime
    }

    func defaultWindow(on date: Date) -> WindowSetup {
        WindowSetup(bedtime: bedtime(on: date),
                    settlingMinutes: defaultSettlingMinutes,
                    pauseCount: defaultPauseCount,
                    pauseLengthMinutes: defaultPauseLengthMinutes,
                    snackBreakMinutes: defaultSnackBreakMinutes,
                    bufferMinutes: defaultBufferMinutes)
    }
}

// MARK: - The document

struct AppDocument: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var profile: HouseProfile
    var viewers: [Viewer]
    var titles: [Title]
    var rules: [HouseRule]
    var ruleHistory: [RuleHistoryEntry]
    var evenings: [Evening]
    var contentNotes: [ContentNote]
    var screenTimeExceptions: [ScreenTimeException]

    init(schemaVersion: Int = AppDocument.currentSchemaVersion,
         profile: HouseProfile = HouseProfile(),
         viewers: [Viewer] = [],
         titles: [Title] = [],
         rules: [HouseRule] = [],
         ruleHistory: [RuleHistoryEntry] = [],
         evenings: [Evening] = [],
         contentNotes: [ContentNote] = [],
         screenTimeExceptions: [ScreenTimeException] = []) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.viewers = viewers
        self.titles = titles
        self.rules = rules
        self.ruleHistory = ruleHistory
        self.evenings = evenings
        self.contentNotes = contentNotes
        self.screenTimeExceptions = screenTimeExceptions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, 1)
        profile = c.value(.profile, HouseProfile())
        viewers = c.value(.viewers, [Viewer]())
        titles = c.value(.titles, [Title]())
        rules = c.value(.rules, [HouseRule]())
        ruleHistory = c.value(.ruleHistory, [RuleHistoryEntry]())
        evenings = c.value(.evenings, [Evening]())
        contentNotes = c.value(.contentNotes, [ContentNote]())
        screenTimeExceptions = c.value(.screenTimeExceptions, [ScreenTimeException]())
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profile, viewers, titles, rules, ruleHistory
        case evenings, contentNotes, screenTimeExceptions
    }
}

// MARK: - Formatting helpers shared by entities and views

enum TimeFormat {
    static func clock(seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func clockLong(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "1 h 44 m" / "92 minutes" style, kept plain-spoken.
    static func minutes(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) min" }
        let h = m / 60, rest = m % 60
        return rest == 0 ? "\(h) h" : "\(h) h \(rest) min"
    }

    static func minutesSentence(_ minutes: Int) -> String {
        let m = max(0, minutes)
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}
