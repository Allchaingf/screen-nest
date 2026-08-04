//  Certifications.swift
//  Screen Nest
//
//  Four classification systems, kept separate on purpose. The app never converts
//  one country's certificate into another's — if a title has no certificate for
//  your country, the field stays empty and says so.

import Foundation

enum RatingCountry: String, Codable, CaseIterable, Identifiable {
    case es, gb, us, ru
    var id: String { rawValue }

    var countryName: String {
        switch self {
        case .es: return "Spain"
        case .gb: return "United Kingdom"
        case .us: return "United States"
        case .ru: return "Russia"
        }
    }

    /// The body that actually issues the certificate.
    var bodyName: String {
        switch self {
        case .es: return "ICAA"
        case .gb: return "BBFC"
        case .us: return "MPA"
        case .ru: return "Age Rating (FZ-436)"
        }
    }

    var displayName: String { "\(countryName) · \(bodyName)" }

    /// ISO code TMDB uses for release certifications.
    var isoCode: String {
        switch self {
        case .es: return "ES"
        case .gb: return "GB"
        case .us: return "US"
        case .ru: return "RU"
        }
    }

    var certifications: [Certification] {
        switch self {
        case .es:
            return [
                Certification(code: "APTA", minimumAge: 0, note: "Suitable for all audiences."),
                Certification(code: "7", minimumAge: 7, note: "Not recommended under 7."),
                Certification(code: "12", minimumAge: 12, note: "Not recommended under 12."),
                Certification(code: "16", minimumAge: 16, note: "Not recommended under 16."),
                Certification(code: "18", minimumAge: 18, note: "Not recommended under 18.")
            ]
        case .gb:
            return [
                Certification(code: "U", minimumAge: 0, note: "Suitable for all."),
                Certification(code: "PG", minimumAge: 0, advisory: true,
                              note: "General viewing, but some scenes may be unsuitable for young children."),
                Certification(code: "12A", minimumAge: 12, adultAccompanimentAllowed: true,
                              note: "Under 12s admitted only with an adult."),
                Certification(code: "12", minimumAge: 12, note: "Suitable for 12 years and over."),
                Certification(code: "15", minimumAge: 15, note: "Suitable only for 15 years and over."),
                Certification(code: "18", minimumAge: 18, note: "Suitable only for adults.")
            ]
        case .us:
            return [
                Certification(code: "G", minimumAge: 0, note: "General audiences."),
                Certification(code: "PG", minimumAge: 0, advisory: true,
                              note: "Parental guidance suggested."),
                Certification(code: "PG-13", minimumAge: 13,
                              note: "Parents strongly cautioned; some material unsuitable under 13."),
                Certification(code: "R", minimumAge: 17, adultAccompanimentAllowed: true,
                              note: "Under 17 requires an accompanying adult."),
                Certification(code: "NC-17", minimumAge: 18, note: "Adults only.")
            ]
        case .ru:
            return [
                Certification(code: "0+", minimumAge: 0, note: "No age restriction."),
                Certification(code: "6+", minimumAge: 6, note: "For viewers over 6."),
                Certification(code: "12+", minimumAge: 12, note: "For viewers over 12."),
                Certification(code: "16+", minimumAge: 16, note: "For viewers over 16."),
                Certification(code: "18+", minimumAge: 18, note: "For adults.")
            ]
        }
    }

    func certification(code: String) -> Certification? {
        let normalised = code.trimmingCharacters(in: .whitespaces).uppercased()
        return certifications.first { $0.code.uppercased() == normalised }
    }

    /// Minimum age for a code, or nil when the code is not part of this system.
    func minimumAge(for code: String?) -> Int? {
        guard let code = code, !code.isEmpty else { return nil }
        return certification(code: code)?.minimumAge
    }

    /// Ordering index used to compare "no higher than" house rules.
    func rank(of code: String?) -> Int? {
        guard let code = code, let cert = certification(code: code) else { return nil }
        return certifications.firstIndex(where: { $0.code == cert.code })
    }
}

struct Certification: Hashable, Identifiable {
    let code: String
    let minimumAge: Int
    /// True for PG-style certificates: no age bar, an explicit call for a parent's judgement.
    var advisory: Bool = false
    /// True where a younger viewer is admitted with an adult (12A, R).
    var adultAccompanimentAllowed: Bool = false
    let note: String

    var id: String { code }
}
