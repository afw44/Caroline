//
//  Config.swift
//  Caroline
//
//  Created by Alexander Weiss on 14/08/2025.
//

import Foundation
import Combine

let ALL_GENTS: [String] = ["gent-1", "gent-2", "gent-3", "gent-4", "gent-5"]

let CurrentEnv: BackendEnv = .local
let BASE_HTTP = CurrentEnv.baseHTTP
let BASE_WS   = CurrentEnv.baseWS

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


enum UserRole { case manager, gent }


enum AppSection: Hashable {
    case manager
    case gent
}

enum Tool: Hashable {
    case gigs
    case calendar
    case accounting
    case availability
}

struct Gig: Identifiable, Codable, Hashable {
    let id: String
    var date: String
    var client_email: String
    var fee: Int                // cents (backend uses int)
    var gents: [String]?        // only present on manager endpoints
    var notes: String?
}


final class Realtime: ObservableObject {
    @Published var isRed: Bool = false     // not used for gigs, keep if you still want color demo
    @Published var connectedGentId: String?
    var onGigsChanged: (() -> Void)?

    private var task: URLSessionWebSocketTask?

    func connect(as gentId: String) {
        connectedGentId = gentId
        // open socket
        var comps = URLComponents(string: "\(BASE_WS)/ws")!
        comps.queryItems = [URLQueryItem(name: "user_id", value: gentId)]
        guard let url = comps.url else { return }
        task?.cancel()
        let ws = URLSession.shared.webSocketTask(with: url)
        task = ws
        ws.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let s)):
                if let data = s.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = obj["type"] as? String {
                    if type == "gigs_changed" {
                        DispatchQueue.main.async { self.onGigsChanged?() }
                    } else if type == "state", let red = obj["red"] as? Bool {
                        // keep compatibility with earlier color demo
                        DispatchQueue.main.async { self.isRed = red }
                    }
                }
            default: break
            }
            self.receive()
        }
    }
}
