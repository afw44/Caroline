//
//  gigDetailView.swift
//  caroline
//
//  Created by Alexander Weiss on 17/08/2025.
//

import SwiftUI

struct GigDetailView: View {
    // Input
    var gig: Gig
    let allGents: [Gent]
    let canEdit: Bool
    var startEditing: Bool = false
    var onSave: (Gig) -> Void
    var onSetPhase: (Phase) -> Void

    // Availability deps (provided by ContentView/AppState)
    var fetchAvailability: (_ gigID: Int) async -> [AvailabilityEntry]
    var setAvailability: (_ gigID: Int, _ gentID: Int, _ status: AvailabilityStatus) async -> Void
    var currentGentID: Int?

    // Local state
    @State private var isEditing: Bool = false
    @State private var draft: Gig
    @State private var feeText: String = ""
    @State private var showAssignments: Bool = true

    // Availability state
    @State private var availability: [AvailabilityEntry] = []
    @State private var isLoadingAvail = false

    init(
        gig: Gig,
        allGents: [Gent],
        canEdit: Bool,
        startEditing: Bool = false,
        onSave: @escaping (Gig) -> Void,
        onSetPhase: @escaping (Phase) -> Void,
        fetchAvailability: @escaping (_ gigID: Int) async -> [AvailabilityEntry],
        setAvailability: @escaping (_ gigID: Int, _ gentID: Int, _ status: AvailabilityStatus) async -> Void,
        currentGentID: Int?
    ) {
        self.gig = gig
        self.allGents = allGents
        self.canEdit = canEdit
        self.startEditing = startEditing
        self.onSave = onSave
        self.onSetPhase = onSetPhase
        self.fetchAvailability = fetchAvailability
        self.setAvailability = setAvailability
        self.currentGentID = currentGentID
        _draft = State(initialValue: gig)
        _isEditing = State(initialValue: startEditing && canEdit)
        _feeText = State(initialValue: String(gig.fee))
        _showAssignments = State(initialValue: true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ===== Header Card =====
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        if isEditing {
                            TextField("Title", text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2.weight(.semibold))
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                Text(draft.title.isEmpty ? "Untitled Gig" : draft.title)
                                    .font(.title2.weight(.semibold))
                                Spacer()
                                PhaseBadge(phase: draft.phase)
                            }
                        }

                        HStack(spacing: 16) {
                            labeled("Date") {
                                if isEditing {
                                    DatePicker("", selection: $draft.date, displayedComponents: [.date]).labelsHidden()
                                } else {
                                    Text(draft.date.formatted(date: .long, time: .omitted))
                                }
                            }
                            Divider().frame(height: 32)
                            labeled("Fee") {
                                if isEditing {
                                    TextField("0", text: $feeText).textFieldStyle(.roundedBorder)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                } else {
                                    Text(draft.fee.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                                }
                            }
                            Divider().frame(height: 32)
                            labeled("Phase") {
                                if isEditing {
                                    Picker("", selection: $draft.phase) {
                                        ForEach(Phase.allCases) { p in Text(p.label).tag(p) }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 280)
                                } else {
                                    Text(draft.phase.label)
                                }
                            }
                        }
                    }
                }

                // ===== Notes =====
                Card(header: "Notes") {
                    if isEditing {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 140)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        if draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("No notes").foregroundStyle(.secondary)
                        } else {
                            Text(draft.notes).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // ===== Availability (Planning only) =====
                if draft.phase == .planning {
                    AvailabilityCard(
                        gigID: draft.id,
                        allGents: allGents,
                        availability: availability,
                        isLoading: isLoadingAvail,
                        canEditAll: canEdit,                 // manager can edit all
                        currentGentID: currentGentID,        // gent can edit own row
                        onChange: { gentID, newStatus in
                            // --- OPTIMISTIC UPDATE ---
                            var dict = availabilityDict
                            dict[gentID] = newStatus
                            availability = allGents.map { g in
                                AvailabilityEntry(gent_id: g.id, status: dict[g.id] ?? .no_reply)
                            }
                            // keep assignments chips in sync locally
                            if newStatus == .assigned {
                                if !draft.gent_ids.contains(gentID) { draft.gent_ids.append(gentID) }
                            } else {
                                draft.gent_ids.removeAll { $0 == gentID }
                            }

                            Task {
                                // server call (AppState will refresh gigs)
                                await setAvailability(draft.id, gentID, newStatus)
                                // pull the canonical availability back
                                await reloadAvailability()
                            }
                        }
                    )
                }

                // ===== Assignments =====
                Card {
                    DisclosureGroup(isExpanded: $showAssignments) {
                        VStack(alignment: .leading, spacing: 8) {
                            if draft.phase == .planning {
                                assignedChips // read-only in planning (availability drives assignment)
                            } else {
                                if isEditing {
                                    ForEach(allGents) { gent in
                                        Toggle(isOn: Binding(
                                            get: { draft.gent_ids.contains(gent.id) },
                                            set: { on in
                                                if on {
                                                    if !draft.gent_ids.contains(gent.id) { draft.gent_ids.append(gent.id) }
                                                } else {
                                                    draft.gent_ids.removeAll { $0 == gent.id }
                                                }
                                            })) {
                                                Text(gent.name)
                                            }
                                    }
                                } else {
                                    assignedChips
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Text("Assignments").font(.headline)
                            Spacer()
                            Text("\(draft.gent_ids.count) selected").foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(showAssignments ? 180 : 0))
                                .animation(.easeInOut(duration: 0.2), value: showAssignments)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(draft.title.isEmpty ? "Gig" : draft.title)
        .toolbar {
            if canEdit {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            draft = gig
                            feeText = String(gig.fee)
                            isEditing = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let f = Double(feeText.replacingOccurrences(of: ",", with: ".")) { draft.fee = f }
                            onSave(draft)
                            isEditing = false
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                } else {
                    // Phase quick menu
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(Phase.allCases) { p in
                                Button {
                                    onSetPhase(p)
                                } label: {
                                    Label(p.label, systemImage: p == gig.phase ? "checkmark" : "")
                                }
                            }
                        } label: { Label("Phase", systemImage: "flag") }
                    }
                    // Separate Edit button
                    ToolbarItem(placement: .automatic) { Button("Edit") { startEditingNow() } }
                }
            }
        }
        .onAppear { Task { await reloadAvailabilityIfNeeded() } }
        .onChange(of: gig) { _, new in
            // keep local draft synced with source of truth
            draft = new
        }
        .onChange(of: gig.id) { _, _ in
            feeText = String(gig.fee)
            isEditing = startEditing && canEdit && gig.id == -1
            showAssignments = true
            Task { await reloadAvailabilityIfNeeded() }
        }
        .onChange(of: draft.phase) { _, _ in
            Task { await reloadAvailabilityIfNeeded() }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var assignedChips: some View {
        let assigned = allGents.filter { draft.gent_ids.contains($0.id) }
        return Group {
            if assigned.isEmpty {
                Text("No gents assigned").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(assigned) { gent in
                        Text(gent.name)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func startEditingNow() {
        draft = gig
        feeText = String(gig.fee)
        isEditing = true
        showAssignments = true
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private var availabilityDict: [Int: AvailabilityStatus] {
        Dictionary(uniqueKeysWithValues: availability.map { ($0.gent_id, $0.status) })
    }

    private func reloadAvailabilityIfNeeded() async {
        guard draft.phase == .planning else {
            availability = []
            return
        }
        await reloadAvailability()
    }

    private func reloadAvailability() async {
        isLoadingAvail = true
        let rows = await fetchAvailability(draft.id)
        isLoadingAvail = false
        availability = rows
    }
}

