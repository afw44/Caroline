//
//  AppState.swift
//  caroline
//
//  Created by Alexander Weiss on 17/08/2025.
//

import Foundation


@MainActor
class AppState: ObservableObject {
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
    func deleteGig(_ gig: Gig) async {
        do {
            try await api.deleteGig(id: gig.id)
        } catch {
            print("delete error:", error)
        }
        do {
            try await refreshGigs()
            if selectedGig?.id == gig.id {
                selectedGig = gigs.first
            }
        } catch {
            print("refresh after delete error:", error)
        }
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


