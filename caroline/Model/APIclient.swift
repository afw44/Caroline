//
//  APIclient.swift
//  caroline
//
//  Created by Alexander Weiss on 17/08/2025.
//

import Foundation

class APIClient {
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

    func deleteGig(id: Int) async throws {
        var comps = URLComponents(url: baseHTTP.appendingPathComponent("gigs/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "actor_role", value: "manager")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        switch http.statusCode {
        case 204, 200, 404:
            return
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "APIClient.deleteGig",
                          code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) on DELETE /gigs/\(id). Body: \(body)"])
        }
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
