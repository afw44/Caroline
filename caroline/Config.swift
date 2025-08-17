//
//  Config.swift
//  Caroline
//
//  Created by Alexander Weiss on 14/08/2025.
//

import Foundation
import Combine

enum Role: String, CaseIterable, Identifiable { case manager, gent; var id: String { rawValue } }

let CurrentEnv: BackendEnv = .local
let BASE_HTTP = CurrentEnv.baseHTTP
let BASE_WS   = CurrentEnv.baseWS



struct Gent: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let username: String?
}

struct Gig: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var date: Date
    var fee: Double
    var notes: String
    var gent_ids: [Int]
}

extension JSONDecoder {
    static var app: JSONDecoder {
        let d = JSONDecoder()
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        d.dateDecodingStrategy = .formatted(df)
        return d
    }
}

extension JSONEncoder {
    static var app: JSONEncoder {
        let e = JSONEncoder()
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        e.dateEncodingStrategy = .formatted(df)
        return e
    }
}

struct NewGig: Codable {
    var title: String
    var date: Date
    var fee: Double
    var notes: String
    var gent_ids: [Int]
}



final class APIClient {
    let baseHTTP: URL
    let session: URLSession

    // Uses your global BASE_HTTP string from config
    init(baseHTTPString: String = BASE_HTTP, session: URLSession = .shared) {
        guard let url = URL(string: baseHTTPString) else {
            fatalError("Bad BASE_HTTP: \(baseHTTPString)")
        }
        self.baseHTTP = url
        self.session = session
    }

    // MARK: Gents
    func gents() async throws -> [Gent] {
        let url = baseHTTP.appendingPathComponent("gents")
        let (data, resp) = try await session.data(from: url)
        try Self.ensure200(resp)
        return try JSONDecoder.app.decode([Gent].self, from: data)
    }

    // MARK: Gigs (optional filter)
    func gigs(gentID: Int?) async throws -> [Gig] {
        var url = baseHTTP.appendingPathComponent("gigs")
        if let gentID {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "gent_id", value: String(gentID))]
            url = comps.url!
        }
        let (data, resp) = try await session.data(from: url)
        try Self.ensure200(resp)
        return try JSONDecoder.app.decode([Gig].self, from: data)
    }

    // MARK: Update (PUT)
    func updateGig(_ gig: Gig) async throws -> Gig {
        var req = URLRequest(url: baseHTTP.appendingPathComponent("gigs/\(gig.id)"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder.app.encode(gig)
        let (data, resp) = try await session.data(for: req)
        try Self.ensure200(resp)
        return try JSONDecoder.app.decode(Gig.self, from: data)
    }

    // MARK: Create (POST)
    func createGig(_ new: NewGig) async throws -> Gig {
        var req = URLRequest(url: baseHTTP.appendingPathComponent("gigs"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder.app.encode(new)
        let (data, resp) = try await session.data(for: req)
        try Self.ensure(resp, expected: 201)
        return try JSONDecoder.app.decode(Gig.self, from: data)
    }

    // MARK: - Helpers
    private static func ensure200(_ response: URLResponse) throws {
        try ensure(response, expected: 200)
    }

    private static func ensure(_ response: URLResponse, expected: Int) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == expected else {
            throw NSError(domain: "APIClient",
                          code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
    }
}


enum BackendEnv {
    case local
    case staging

    var baseHTTP: String {
        switch self {
        case .local:
            return "http://127.0.0.1:8000"
        case .staging:
            return "https://giggle2.onrender.com"
        }
    }

    var baseWS: String {
        switch self {
        case .local:
            return "ws://127.0.0.1:8000/ws"
        case .staging:
            return "wss://giggle2.onrender.com"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var role: Role = .gent
    @Published var gents: [Gent] = []
    @Published var selectedGentID: Int? = nil
    @Published var gigs: [Gig] = []
    @Published var selectedGig: Gig? = nil

    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func loadInitial() async {
        do {
            gents = try await api.gents()
            if selectedGentID == nil { selectedGentID = gents.first?.id }
            try await refreshGigs()
        } catch { print("loadInitial error:", error) }
    }

    func refreshGigs() async throws {
        // Decide which gent to filter by
        let filterGentID: Int?
        switch role {
        case .manager: filterGentID = selectedGentID    // nil = all gigs
        case .gent:    filterGentID = selectedGentID    // until auth exists
        }
        let latest = try await api.gigs(gentID: filterGentID)
        gigs = latest.sorted { $0.date < $1.date }
        if let sel = selectedGig?.id { selectedGig = gigs.first(where: { $0.id == sel }) }
    }

    func createGig(from draft: Gig) async {
        do {
            let payload = NewGig(title: draft.title, date: draft.date, fee: draft.fee, notes: draft.notes, gent_ids: draft.gent_ids)
            let created = try await api.createGig(payload)
            try await refreshGigs()                                   // ⬅️ re-fetch
            selectedGig = gigs.first(where: { $0.id == created.id })  // select new one
        } catch { print("create error:", error) }
    }

    func saveGig(_ gig: Gig) async {
        do {
            _ = try await api.updateGig(gig)
            try await refreshGigs()                                   // ⬅️ re-fetch
            selectedGig = gigs.first(where: { $0.id == gig.id })
        } catch { print("save error:", error) }
    }
}

