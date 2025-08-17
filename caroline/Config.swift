//
//  Config.swift
//  Caroline
//
//  Created by Alexander Weiss on 14/08/2025.
//

import Foundation
import SwiftUI

// MARK: - Models

struct Gent: Identifiable, Codable, Hashable {
    var id: Int
    var name: String
    var username: String?
}

struct Gig: Identifiable, Codable, Hashable, Equatable {
    var id: Int
    var title: String
    var date: Date
    var fee: Double
    var notes: String
    var phase: Phase        // <- NEW
    var gent_ids: [Int]
}

// Payload for POST /gigs
struct NewGig: Codable {
    var title: String
    var date: Date
    var fee: Double
    var notes: String
    var phase: Phase        // <- include in payload
    var gent_ids: [Int]
}

enum Role: String, CaseIterable, Identifiable {
    case manager, gent
    var id: String { rawValue }
}

enum Phase: String, Codable, CaseIterable, Identifiable {
    case planning, booked, completed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .planning:  return "Planning"
        case .booked:    return "Booked"
        case .completed: return "Completed"
        }
    }
}

struct AvailabilityEntry: Codable, Hashable, Identifiable {
    var gent_id: Int
    var status: AvailabilityStatus
    var id: Int { gent_id }
}

private struct AvailabilityUpdatePayload: Codable {
    var gent_id: Int
    var status: AvailabilityStatus
}

enum AvailabilityStatus: String, Codable, CaseIterable, Identifiable {
    case no_reply, available, unavailable, assigned
    var id: String { rawValue }

    var label: String {
        switch self {
        case .no_reply:   return "No Reply"
        case .available:  return "Available"
        case .unavailable:return "Unavailable"
        case .assigned:   return "Assigned"
        }
    }
}

let CurrentEnv: BackendEnv = .local
let BASE_HTTP = CurrentEnv.baseHTTP
let BASE_WS   = CurrentEnv.baseWS

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
    
    func availability(gigID: Int) async throws -> [AvailabilityEntry] {
        let url = baseHTTP.appendingPathComponent("gigs/\(gigID)/availability")
        let (data, resp) = try await session.data(from: url)
        try Self.ensure200(resp)
        return try JSONDecoder.app.decode([AvailabilityEntry].self, from: data)
    }
    
    @discardableResult
    func setAvailability(
        gigID: Int,
        gentID: Int,
        status: AvailabilityStatus,
        actorRole: Role,
        actorGentID: Int? = nil
    ) async throws -> AvailabilityEntry {
        var comps = URLComponents(url: baseHTTP.appendingPathComponent("gigs/\(gigID)/availability"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "actor_role", value: actorRole.rawValue),
        ]
        if actorRole == .gent, let actorGentID {
            comps.queryItems?.append(URLQueryItem(name: "actor_gent_id", value: String(actorGentID)))
        }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = AvailabilityUpdatePayload(gent_id: gentID, status: status)
        req.httpBody = try JSONEncoder.app.encode(body)

        let (data, resp) = try await session.data(for: req)
        try Self.ensure200(resp)
        return try JSONDecoder.app.decode(AvailabilityEntry.self, from: data)
    }

    @discardableResult
    func setAvailabilityAsGent(gigID: Int, gentID: Int, status: AvailabilityStatus) async throws -> AvailabilityEntry {
        try await setAvailability(gigID: gigID, gentID: gentID, status: status, actorRole: .gent, actorGentID: gentID)
    }

    @discardableResult
    func setAvailabilityAsManager(gigID: Int, gentID: Int, status: AvailabilityStatus) async throws -> AvailabilityEntry {
        try await setAvailability(gigID: gigID, gentID: gentID, status: status, actorRole: .manager, actorGentID: nil)
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

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var role: Role = .gent
    @Published var gents: [Gent] = []
    @Published var selectedGentID: Int? = nil

    @Published var gigs: [Gig] = []
    @Published var selectedGig: Gig? = nil

    let api: APIClient
    init(api: APIClient) { self.api = api }

    // Initial bootstrap
    func loadInitial() async {
        do {
            gents = try await api.gents()
            if role == .gent, selectedGentID == nil {
                selectedGentID = gents.first?.id
            }
            try await refreshGigs()
        } catch { print("loadInitial error:", error) }
    }

    // Always fetch from backend (authoritative)
    func refreshGigs() async throws {
        let filterGentID: Int?
        switch role {
        case .manager: filterGentID = nil          // manager sees all gigs
        case .gent:    filterGentID = selectedGentID
        }
        let latest = try await api.gigs(gentID: filterGentID)
        gigs = latest.sorted { ($0.date, $0.title) < ($1.date, $1.title) }
        // keep selection if possible
        if let sel = selectedGig?.id {
            selectedGig = gigs.first(where: { $0.id == sel })
        } else {
            selectedGig = gigs.first
        }
    }

    @MainActor
    func loadAvailability(for gigID: Int) async -> [AvailabilityEntry] {
        (try? await api.availability(gigID: gigID)) ?? []
    }

    @MainActor
    func updateAvailability(gigID: Int, gentID: Int, to status: AvailabilityStatus) async {
        do {
            switch role {
            case .manager:
                _ = try await api.setAvailabilityAsManager(gigID: gigID, gentID: gentID, status: status)
            case .gent:
                _ = try await api.setAvailabilityAsGent(gigID: gigID, gentID: gentID, status: status)
            }
            try await refreshGigs() // keep assignments in sync after 'assigned'
        } catch {
            print("availability update error:", error)
        }
    }
    
    // Create from an inline draft
    func createGig(from draft: Gig) async {
        let payload = NewGig(
            title: draft.title,
            date: draft.date,
            fee: draft.fee,
            notes: draft.notes,
            phase: draft.phase,          // <- include
            gent_ids: draft.gent_ids
        )
        do {
            let created = try await api.createGig(payload)
            try await refreshGigs()
            selectedGig = gigs.first(where: { $0.id == created.id })
        } catch { print("create error:", error) }
    }

    // Save edits to an existing gig
    func saveGig(_ gig: Gig) async {
        do {
            _ = try await api.updateGig(gig)   // gig already has .phase
            try await refreshGigs()
            selectedGig = gigs.first(where: { $0.id == gig.id })
        } catch { print("save error:", error) }
    }

    // Convenience for a manager to change just the phase
    func setPhase(for gigID: Int, to phase: Phase) async {
        guard var g = gigs.first(where: { $0.id == gigID }) else { return }
        g.phase = phase
        await saveGig(g)
    }

    // Helper to create a new draft gig with sensible defaults
    func makeDraft(prefill gentID: Int?) -> Gig {
        Gig(
            id: -1,
            title: "New Gig",
            date: Date(),
            fee: 0,
            notes: "",
            phase: .planning,            // <- default phase
            gent_ids: gentID.map { [$0] } ?? []
        )
    }
}


