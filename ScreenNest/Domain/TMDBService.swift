//  TMDBService.swift
//  Screen Nest — external data.
//
//  Rules this file obeys, from the specification:
//   • a request happens only because the parent pressed something;
//   • nothing is pre-fetched, and no catalogue is mirrored;
//   • every answer is written to a local cache and works again offline;
//   • the certificate is read for the country in Settings and for no other —
//     when there is none, the field stays empty and says why.
//
//  No SDK, no package: URLSession and JSONSerialization only.

import Foundation
import Network
import UIKit

// MARK: - Search result

struct TMDBSearchResult: Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String
    let year: Int?
    let isSeries: Bool
    let overview: String
    let posterPath: String?

    var typeLabel: String { isSeries ? "Series" : "Film" }
}

/// Everything the detail lookup can fill in. Each field is optional so the form
/// can mark what genuinely arrived.
struct TMDBDetail {
    var runtimeMinutes: Int?
    var genres: [String] = []
    var overview: String?
    var year: Int?
    var certification: String?
    var certificationMissing: Bool = false
    var aspects: [ContentAspect] = []
    var posterPath: String?
    var seasons: [SeriesSeason] = []
}

enum TMDBError: LocalizedError {
    case missingKey
    case disabled
    case offline
    case notFound
    case busy
    case failed

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Online search is not available in this build. Add the title by hand — every other part of the app works exactly the same."
        case .disabled:
            return "Online search is switched off in Settings → External Data. You can add titles by hand as usual."
        case .offline:
            return "Offline. You can add titles by hand, plan the evening and watch — only online search is unavailable."
        case .notFound:
            return "Nothing found. Check the title or add it by hand."
        case .busy:
            return "Search service is busy. Add the film manually — you can fill in the details later."
        case .failed:
            return "The search could not be completed. Add the film manually — you can fill in the details later."
        }
    }
}

// MARK: - Reachability

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "nest.network")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Service

final class TMDBService {

    static let shared = TMDBService()

    static let attribution = "This product uses the TMDB API but is not endorsed or certified by TMDB."

    private let base = "https://api.themoviedb.org/3"
    private let imageBase = "https://image.tmdb.org/t/p/w500"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// Compiled in — see TMDBConfig. The parent is never asked for a key.
    private var apiKey: String {
        TMDBConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasKey: Bool { TMDBConfig.isConfigured }

    /// A v4 read access token is a JWT: three dot-separated parts. A v3 key is
    /// a plain 32-character hex string.
    private var isBearerToken: Bool {
        apiKey.split(separator: ".").count == 3
    }

    /// The one network control the parent has: off means off.
    var isAllowed: Bool {
        UserDefaults.standard.object(forKey: NestDefaults.tmdbEnabled) as? Bool ?? true
    }

    var isEnabled: Bool { isAllowed && hasKey }

    // MARK: - Cache

    private var cacheDirectory: URL { DataStore.shared.cacheDirectory }

    private func cacheURL(for key: String) -> URL {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "entry"
        return cacheDirectory.appendingPathComponent("\(safe).json")
    }

    private func readCache(_ key: String) -> Any? {
        guard let data = try? Data(contentsOf: cacheURL(for: key)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func writeCache(_ key: String, _ data: Data) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL(for: key), options: .atomic)
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    var cacheSizeDescription: String {
        let urls = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                 includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = urls.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        if bytes == 0 { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(urls.count) entries · \(formatter.string(fromByteCount: Int64(bytes)))"
    }

    // MARK: - Requests

    private func fetch(path: String, query: [String: String], cacheKey: String) async throws -> [String: Any] {
        guard isAllowed else { throw TMDBError.disabled }
        guard hasKey else { throw TMDBError.missingKey }

        var components = URLComponents(string: base + path)
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        // A v3 key travels in the query string; a v4 read token travels in the
        // Authorization header. Both are accepted so either can be pasted in.
        if !isBearerToken {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw TMDBError.failed }

        var request = URLRequest(url: url)
        if isBearerToken {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200...299: break
                case 429, 503: throw TMDBError.busy
                case 401: throw TMDBError.missingKey
                default: throw TMDBError.failed
                }
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TMDBError.failed
            }
            writeCache(cacheKey, data)
            return json
        } catch let error as TMDBError {
            throw error
        } catch {
            // Fall back to whatever the cache already holds before reporting failure.
            if let cached = readCache(cacheKey) as? [String: Any] { return cached }
            let code = (error as NSError).code
            if code == NSURLErrorNotConnectedToInternet || code == NSURLErrorNetworkConnectionLost {
                throw TMDBError.offline
            }
            throw TMDBError.failed
        }
    }

    // MARK: - Search

    func search(_ term: String) async throws -> [TMDBSearchResult] {
        // Checked here too: with the switch off, not even the cache is consulted.
        guard isAllowed else { throw TMDBError.disabled }
        guard hasKey else { throw TMDBError.missingKey }
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let key = "search-\(trimmed.lowercased())"

        // Offline: serve the cache if we have been asked this before.
        if !NetworkMonitor.shared.isOnline {
            if let cached = readCache(key) as? [String: Any] {
                return parseSearch(cached)
            }
            throw TMDBError.offline
        }

        let json = try await fetch(path: "/search/multi",
                                   query: ["query": trimmed, "include_adult": "false"],
                                   cacheKey: key)
        let results = parseSearch(json)
        if results.isEmpty { throw TMDBError.notFound }
        return results
    }

    private func parseSearch(_ json: [String: Any]) -> [TMDBSearchResult] {
        let raw = json["results"] as? [[String: Any]] ?? []
        return raw.compactMap { entry in
            let mediaType = entry["media_type"] as? String ?? "movie"
            guard mediaType == "movie" || mediaType == "tv" else { return nil }
            guard let id = entry["id"] as? Int else { return nil }
            let isSeries = mediaType == "tv"
            let name = (isSeries ? entry["name"] : entry["title"]) as? String ?? ""
            guard !name.isEmpty else { return nil }
            let original = (isSeries ? entry["original_name"] : entry["original_title"]) as? String ?? name
            let dateString = (isSeries ? entry["first_air_date"] : entry["release_date"]) as? String ?? ""
            let year = Int(dateString.prefix(4))
            return TMDBSearchResult(id: id,
                                    name: name,
                                    originalName: original,
                                    year: year,
                                    isSeries: isSeries,
                                    overview: entry["overview"] as? String ?? "",
                                    posterPath: entry["poster_path"] as? String)
        }
    }

    // MARK: - Detail

    func detail(for result: TMDBSearchResult, country: RatingCountry) async throws -> TMDBDetail {
        guard isAllowed else { throw TMDBError.disabled }
        guard hasKey else { throw TMDBError.missingKey }
        let path = result.isSeries ? "/tv/\(result.id)" : "/movie/\(result.id)"
        let append = result.isSeries ? "content_ratings,keywords" : "release_dates,keywords"
        let key = "detail-\(result.isSeries ? "tv" : "movie")-\(result.id)"

        var json: [String: Any]
        if !NetworkMonitor.shared.isOnline {
            guard let cached = readCache(key) as? [String: Any] else { throw TMDBError.offline }
            json = cached
        } else {
            json = try await fetch(path: path, query: ["append_to_response": append], cacheKey: key)
        }

        var detail = TMDBDetail()
        detail.overview = json["overview"] as? String
        detail.posterPath = json["poster_path"] as? String

        if result.isSeries {
            let runtimes = json["episode_run_time"] as? [Int] ?? []
            detail.runtimeMinutes = runtimes.first
            detail.year = Int(((json["first_air_date"] as? String) ?? "").prefix(4))
            detail.seasons = parseSeasons(json, fallbackRuntime: runtimes.first ?? 24)
            detail.certification = seriesCertification(json, country: country)
        } else {
            detail.runtimeMinutes = json["runtime"] as? Int
            detail.year = Int(((json["release_date"] as? String) ?? "").prefix(4))
            detail.certification = movieCertification(json, country: country)
        }
        detail.certificationMissing = (detail.certification?.isEmpty ?? true)

        detail.genres = (json["genres"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        detail.aspects = aspects(from: json)
        return detail
    }

    private func parseSeasons(_ json: [String: Any], fallbackRuntime: Int) -> [SeriesSeason] {
        let raw = json["seasons"] as? [[String: Any]] ?? []
        return raw.compactMap { entry in
            guard let number = entry["season_number"] as? Int, number > 0 else { return nil }
            let count = entry["episode_count"] as? Int ?? 0
            guard count > 0 else { return nil }
            let episodes = (1...count).map { index in
                Episode(number: index, name: "Episode \(index)", runtimeMinutes: max(1, fallbackRuntime))
            }
            return SeriesSeason(number: number,
                                name: entry["name"] as? String ?? "Season \(number)",
                                episodes: episodes)
        }
    }

    /// Certificate for the chosen country only. Never substituted from elsewhere.
    private func movieCertification(_ json: [String: Any], country: RatingCountry) -> String? {
        let releases = (json["release_dates"] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        guard let entry = releases.first(where: { ($0["iso_3166_1"] as? String) == country.isoCode }) else { return nil }
        let dates = entry["release_dates"] as? [[String: Any]] ?? []
        let codes = dates.compactMap { $0["certification"] as? String }.filter { !$0.isEmpty }
        guard let code = codes.first else { return nil }
        // Only accept a code this country's system actually uses.
        return country.certification(code: code)?.code
    }

    private func seriesCertification(_ json: [String: Any], country: RatingCountry) -> String? {
        let ratings = (json["content_ratings"] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        guard let entry = ratings.first(where: { ($0["iso_3166_1"] as? String) == country.isoCode }),
              let code = entry["rating"] as? String, !code.isEmpty else { return nil }
        return country.certification(code: code)?.code
    }

    // MARK: - Keywords → content aspects

    private static let keywordMap: [String: ContentAspect] = [
        "monster": .horror, "horror": .horror, "haunting": .horror, "ghost": .horror,
        "jump scare": .jumpScares, "supernatural": .jumpScares,
        "dark": .darkness, "night": .darkness,
        "dog": .animalInDanger, "animal": .animalInDanger, "wolf": .animalInDanger,
        "orphan": .parentSeparation, "adoption": .parentSeparation, "lost child": .parentSeparation,
        "death": .characterDeath, "funeral": .characterDeath, "grief": .sadEndings,
        "bullying": .bullying, "school bully": .bullying,
        "hospital": .medicalScenes, "surgery": .medicalScenes, "illness": .medicalScenes,
        "sad": .sadEndings, "tragedy": .sadEndings,
        "chase": .fastCutting, "action": .fastCutting,
        "suspense": .suspense, "thriller": .suspense,
        "violence": .realisticViolence, "war": .realisticViolence, "battle": .realisticViolence,
        "profanity": .strongLanguage, "swearing": .strongLanguage
    ]

    private func aspects(from json: [String: Any]) -> [ContentAspect] {
        let keywordsNode = json["keywords"] as? [String: Any]
        let list = (keywordsNode?["keywords"] as? [[String: Any]])
            ?? (keywordsNode?["results"] as? [[String: Any]])
            ?? []
        let names = list.compactMap { ($0["name"] as? String)?.lowercased() }
        var found: [ContentAspect] = []
        for name in names {
            for (needle, aspect) in TMDBService.keywordMap where name.contains(needle) {
                if !found.contains(aspect) { found.append(aspect) }
            }
        }
        return found
    }

    // MARK: - Posters

    func posterImage(path: String?) async -> UIImage? {
        guard isAllowed, let path = path, !path.isEmpty,
              let url = URL(string: imageBase + path) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
