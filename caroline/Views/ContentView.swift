import SwiftUI

#Preview { ContentView() }

struct ContentView: View {
    @StateObject private var state = AppState(api: APIClient())

    @State private var showProfilePanel = false

    var body: some View {
        gigView(state: state)
            .task { await state.loadInitial() }
            .onChange(of: state.role) { _, _ in
                if state.role == .gent, state.selectedGentID == nil {
                    state.selectedGentID = state.gents.first?.id
                }
                Task { try? await state.refreshGigs() }
            }
            .onChange(of: state.selectedGentID) { _, _ in
                Task { try? await state.refreshGigs() }
            }

            .safeAreaInset(edge: .bottom) {
                BottomBar {
                    Button { /* future tab */ } label: {
                        Image(systemName: "house").font(.title2)
                    }
                    Spacer()
                    Button { /* future tab */ } label: {
                        Image(systemName: "plus.app").font(.title2)
                    }
                    Spacer()
                    // 🔹 Person (profile) — opens picker controls
                    Button { showProfilePanel.toggle() } label: {
                        Image(systemName: "person.crop.circle").font(.title2)
                    }
                    // present panel from the button
                    .profilePanel(isPresented: $showProfilePanel, state: state)
                }
            }

            // iPhone push behavior (unchanged)
            .navigationDestination(item: $state.selectedGig) { gig in
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
            }
    }
}

// MARK: - Bottom bar chrome (unchanged)
private struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .frame(height: 60)
                .overlay(Divider(), alignment: .top)
            HStack(spacing: 24) { content }
                .padding(.horizontal, 20)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Profile panel CONTENT (no popover/sheet here)
private struct ProfilePanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("Role") {
                Picker("Role", selection: $state.role) {
                    ForEach(Role.allCases) { r in
                        Text(r.rawValue.capitalized).tag(r)
                    }
                }
                .pickerStyle(.inline)
            }
            if state.role == .gent {
                Section("I am…") {
                    Picker("Gent", selection: Binding(
                        get: { state.selectedGentID ?? -1 },
                        set: { newValue in
                            state.selectedGentID = (newValue == -1) ? nil : newValue
                        }
                    )) {
                        ForEach(state.gents) { g in
                            Text(g.name).tag(g.id)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        }
        .onChange(of: state.role) { _, _ in
            if state.role == .gent, state.selectedGentID == nil {
                state.selectedGentID = state.gents.first?.id
            }
            Task { try? await state.refreshGigs() }
        }
        .onChange(of: state.selectedGentID) { _, _ in
            Task { try? await state.refreshGigs() }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        .frame(minHeight: 180)
        .padding(.top, 8)
    }
}

// MARK: - Presenter so `.profilePanel(isPresented:state:)` works
private struct ProfilePanelPresenter: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ProfilePanel(state: state).padding()
        }
        #else
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                ProfilePanel(state: state)
                    .navigationTitle("Profile")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isPresented = false }
                        }
                    }
            }
            .presentationDetents([ .medium, .large ])
        }
        #endif
    }
}

private extension View {
    func profilePanel(isPresented: Binding<Bool>, state: AppState) -> some View {
        modifier(ProfilePanelPresenter(isPresented: isPresented, state: state))
    }
}


struct GigList: View {
    
    @ObservedObject var state: AppState
    
    @State private var expandedPhases: Set<Phase> = [.planning, .booked, .completed]
    private let phaseOrder: [Phase] = [.planning, .booked, .completed]
    @State private var confirmDelete: Gig? = nil
    
    var body: some View{
        
        List {
                ForEach(phaseOrder, id: \.self) { phase in
                    let gigsInPhase = state.gigs.filter { $0.phase == phase }
                    if !gigsInPhase.isEmpty {                 // hide empty phases
                        Section {
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedPhases.contains(phase) },
                                    set: { open in
                                        if open { expandedPhases.insert(phase) }
                                        else { expandedPhases.remove(phase) }
                                    }
                                )
                            ) {
                                ForEach(gigsInPhase) { gig in
                                    Button {
                                        state.selectedGig = gig
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(gig.title).font(.headline)
                                            HStack {
                                                Text(gig.date.formatted(date: .abbreviated, time: .omitted))
                                                Spacer()
                                                Text(gig.fee, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(
                                        (state.selectedGig?.id == gig.id)
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear
                                    )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        if state.role == .manager {
                                            Button(role: .destructive) {
                                                confirmDelete = gig
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    PhaseBadge(phase: phase)   // only header shows the flag
                                    Text(phase.label).font(.headline)
                                    Spacer()
                                    Text("\(gigsInPhase.count)")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                    Image(systemName: "chevron.down")
                                        .rotationEffect(.degrees(expandedPhases.contains(phase) ? 180 : 0))
                                        .animation(.easeInOut(duration: 0.2), value: expandedPhases)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .onChange(of: state.role) { _, _ in
                if state.role == .gent, state.selectedGentID == nil {
                    state.selectedGentID = state.gents.first?.id
                }
                Task { try? await state.refreshGigs() }
            }
            .onChange(of: state.selectedGentID) { _, _ in
                Task { try? await state.refreshGigs() }
            }
            .refreshable { try? await state.refreshGigs() }
            .toolbar {
                // Manager-only: Add Gig
                if state.role == .manager {
                    Button {
                        state.selectedGig = state.makeDraft(prefill: state.selectedGentID)
                        expandedPhases.insert(.planning)
                    } label: {
                        Label("Add Gig", systemImage: "plus")
                    }
                }
                // Expand/Collapse is useful for everyone
                Menu {
                    Button("Expand All") { expandedPhases = Set(phaseOrder) }
                    Button("Collapse All") { expandedPhases.removeAll() }
                } label: {
                    Label("Sections", systemImage: "rectangle.split.3x1")
                }
            }
            .navigationTitle("Gigs")
            .alert("Delete gig?", isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let g = confirmDelete {
                        Task { await state.deleteGig(g) }
                    }
                    confirmDelete = nil
                }
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            } message: {
                Text(confirmDelete.map { "“\($0.title)” will be removed." } ?? "")
            }
        
    }
}
