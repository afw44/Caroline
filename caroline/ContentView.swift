import SwiftUI

import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState(api: APIClient())

    private func newDraftGig(prefill gentID: Int?) -> Gig {
        Gig(id: -1, title: "New Gig", date: Date(), fee: 0, notes: "", gent_ids: gentID.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationSplitView {
            // ========== SIDEBAR ==========
            List {
                Section("Role") {
                    Picker("Role", selection: $state.role) {
                        ForEach(Role.allCases) { r in
                            Text(r.rawValue.capitalized).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Picker shows when *Gent* is the role
                if state.role == .gent {
                    Section("I am…") {
                        Picker("Gent", selection: Binding(
                            get: { state.selectedGentID ?? -1 },
                            set: { newValue in
                                state.selectedGentID = (newValue == -1) ? nil : newValue
                                Task { try? await state.refreshGigs() }
                            }
                        )) {
                            ForEach(state.gents) { g in
                                Text(g.name).tag(g.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Giggle")
            .onChange(of: state.role) { _, _ in
                if state.role == .gent, state.selectedGentID == nil {
                    state.selectedGentID = state.gents.first?.id
                }
                Task { try? await state.refreshGigs() }
            }
            .task { await state.loadInitial() }

        } content: {
            // ========== MIDDLE LIST (button rows driving selection) ==========
            List {
                ForEach(state.gigs) { gig in
                    Button {
                        state.selectedGig = gig
                    } label: {
                        VStack(alignment: .leading) {
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
                    .buttonStyle(.plain) // so it looks like a row
                    .listRowBackground(
                        (state.selectedGig?.id == gig.id)
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                    )
                }
            }
            .refreshable { try? await state.refreshGigs() }
            .toolbar {
                if state.role == .manager {
                    Button {
                        state.selectedGig = newDraftGig(prefill: state.selectedGentID)
                    } label: {
                        Label("Add Gig", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Gigs")

        } detail: {
            // ========== DETAIL (inline editor) ==========
            if let gig = state.selectedGig {
                GigDetailView(
                    gig: gig,
                    allGents: state.gents,
                    canEdit: state.role == .manager,
                    startEditing: gig.id == -1,
                    onSave: { updated in
                        Task {
                            if updated.id == -1 {
                                await state.createGig(from: updated)  // POST
                            } else {
                                await state.saveGig(updated)          // PUT
                            }
                        }
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a Gig",
                    systemImage: "music.mic",
                    description: Text("Pick a gig from the list")
                )
            }
        }
    }
}

struct GigDetailView: View {
    // Passed from parent (do NOT @State)
    var gig: Gig

    let allGents: [Gent]
    let canEdit: Bool
    var startEditing: Bool = false
    var onSave: (Gig) -> Void

    // Local editing state
    @State private var isEditing: Bool = false
    @State private var draft: Gig
    @State private var feeText: String = ""
    @State private var showAssignments: Bool = false   // dropdown (DisclosureGroup)

    init(
        gig: Gig,
        allGents: [Gent],
        canEdit: Bool,
        startEditing: Bool = false,
        onSave: @escaping (Gig) -> Void
    ) {
        self.gig = gig
        self.allGents = allGents
        self.canEdit = canEdit
        self.startEditing = startEditing
        self.onSave = onSave
        _draft = State(initialValue: gig)
        _isEditing = State(initialValue: startEditing && canEdit)
        _feeText = State(initialValue: String(gig.fee))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ===== Title + Primary Info (Card) =====
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        if isEditing {
                            TextField("Title", text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2.weight(.semibold))
                        } else {
                            Text(draft.title.isEmpty ? "Untitled Gig" : draft.title)
                                .font(.title2.weight(.semibold))
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date").font(.caption).foregroundStyle(.secondary)
                                if isEditing {
                                    DatePicker("", selection: $draft.date, displayedComponents: [.date])
                                        .labelsHidden()
                                } else {
                                    Text(draft.date.formatted(date: .long, time: .omitted))
                                }
                            }

                            Divider().frame(height: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Fee").font(.caption).foregroundStyle(.secondary)
                                if isEditing {
                                    TextField("0", text: $feeText)
                                        .textFieldStyle(.roundedBorder)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                } else {
                                    Text(draft.fee.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                                }
                            }
                        }
                    }
                }

                // ===== Notes (Headed Text Box / Card) =====
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

                // ===== Assignments (Disclosure / Dropdown) =====
                Card {
                    DisclosureGroup(isExpanded: $showAssignments) {
                        VStack(alignment: .leading, spacing: 8) {
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
                                let assigned = allGents.filter { draft.gent_ids.contains($0.id) }
                                if assigned.isEmpty {
                                    Text("No gents assigned").foregroundStyle(.secondary)
                                } else {
                                    // Reliable wrapping chips via adaptive grid
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
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Text("Assignments").font(.headline)
                            Spacer()
                            Text("\(draft.gent_ids.count) selected")
                                .foregroundStyle(.secondary)
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
                            if let f = Double(feeText.replacingOccurrences(of: ",", with: ".")) {
                                draft.fee = f
                            }
                            onSave(draft)
                            isEditing = false
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { startEditingNow() }
                    }
                }
            }
        }
        .onChange(of: gig.id) { _, _ in
            draft = gig
            feeText = String(gig.fee)
            isEditing = startEditing && canEdit && gig.id == -1
        }
    }

    private func startEditingNow() {
        draft = gig
        feeText = String(gig.fee)
        isEditing = true
        showAssignments = true
    }
}

private struct Card<Content: View>: View {
    var header: String?
    @ViewBuilder var content: Content

    init(header: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header { Text(header).font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
