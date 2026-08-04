//  TMDBConfig.swift
//  Screen Nest
//
//  The TMDB key is the developer's, not the parent's — it is compiled into the
//  build and never asked for anywhere in the app.
//
//  ── PASTE THE KEY BETWEEN THE QUOTES BELOW. That is the only edit needed. ──
//
//  Notes for whoever maintains this:
//   • a key inside a shipped iOS binary is extractable, which is normal for a
//     TMDB client key but means it should be treated as rotatable, not secret;
//   • keep this file out of any public repository;
//   • with the key empty the app still works completely — only the online
//     search path reports itself unavailable, and everything is entered by hand.

import Foundation

enum TMDBConfig {

    /// TMDB credential. Both forms are accepted and detected automatically:
    ///  • a v3 API key (32-char hex) — sent as an `api_key` query parameter;
    ///  • a v4 Read Access Token (a JWT) — sent as `Authorization: Bearer …`.
    static let apiKey = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJmNDk5YjM3MTI3MGYzNTk3ZDMzNDMwNzljM2IzN2U1OCIsIm5iZiI6MTU5MTc5MDMzOS4xNSwic3ViIjoiNWVlMGNiMDNmMzZhMzIwMDFmOGY2M2ZjIiwic2NvcGVzIjpbImFwaV9yZWFkIl0sInZlcnNpb24iOjF9.pD-iOgoffFX1bq9AfX4jKLf7KSviMx2D3SDrE0msA38"

    /// True once a key has been compiled in.
    static var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
