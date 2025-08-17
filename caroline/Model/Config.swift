//
//  Config.swift
//  Caroline
//
//  Created by Alexander Weiss on 14/08/2025.
//

import Foundation
import SwiftUI


let CurrentEnv: BackendEnv = .local
let BASE_HTTP = CurrentEnv.baseHTTP

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

}


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

struct AvailabilityUpdatePayload: Codable {
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


