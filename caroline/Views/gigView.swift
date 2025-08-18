//
//  gigView.swift
//  caroline
//
//  Created by Alexander Weiss on 18/08/2025.
//

import SwiftUI

struct gigView: View {
    
    @ObservedObject var state: AppState

    // Track which phase groups are expanded
    
    @State private var showProfilePanel = false
    
    var body: some View {
        
        HSplitView{
            
            GigList(state: state)
            
            if let gig = state.selectedGig {
                GigDetailView(
                    gig: gig,
                    allGents: state.gents,
                    canEdit: state.role == .manager,
                    startEditing: gig.id == -1,
                    onSave: { updated in
                        Task {
                            if updated.id == -1 { await state.createGig(from: updated) }
                            else { await state.saveGig(updated) }
                        }
                    },
                    onSetPhase: { newPhase in
                        Task { await state.setPhase(for: gig.id, to: newPhase) }
                    },
                    fetchAvailability: { id in await state.loadAvailability(for: id) },
                    setAvailability: { id, gentID, status in
                        await state.updateAvailability(gigID: id, gentID: gentID, to: status)
                    },
                    currentGentID: state.role == .gent ? state.selectedGentID : nil
                )
                
            } else {
                ContentUnavailableView(
                    "Select a Gig",
                    systemImage: "music.mic",
                    description: Text("Pick a gig from the list")
                )
            }
            
        }
        .task {
            await state.loadInitial()
        }

        // 2) when role changes, ensure a gent is selected (if needed) and refresh
        .onChange(of: state.role) { _, _ in
            if state.role == .gent, state.selectedGentID == nil {
                state.selectedGentID = state.gents.first?.id
            }
            Task { try? await state.refreshGigs() }
        }

        // 3) when the selected gent changes, refresh
        .onChange(of: state.selectedGentID) { _, _ in
            Task { try? await state.refreshGigs() }
        }
    }
}
