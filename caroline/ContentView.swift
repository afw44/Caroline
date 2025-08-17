import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState(api: APIClient())
    @State private var confirmDelete: Gig? = nil

    // Track which phase groups are expanded
    @State private var expandedPhases: Set<Phase> = [.planning, .booked, .completed]

    // Phase display order
    private let phaseOrder: [Phase] = [.planning, .booked, .completed]

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
                    .pickerStyle(.inline)   // vertical radio-like list
                }

                // Gent-specific filter
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
                        .pickerStyle(.inline)  // also vertical
                    }
                }
            }
            .navigationTitle("Caroline")
            .onChange(of: state.role) { _, _ in
                if state.role == .gent, state.selectedGentID == nil {
                    state.selectedGentID = state.gents.first?.id
                }
                Task { try? await state.refreshGigs() }
            }
            .task { await state.loadInitial() }

        } content: {
            // ========== MIDDLE LIST: grouped by Phase with collapsible sections ==========
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
            
        } detail: {
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
        // iPhone push behavior
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

// MARK: - Availability Card
private struct AvailabilityCard: View {
    let gigID: Int
    let allGents: [Gent]
    let availability: [AvailabilityEntry]
    let isLoading: Bool

    /// Manager can edit all rows (true when role == .manager)
    let canEditAll: Bool

    /// The current gent id if role == .gent, otherwise nil
    let currentGentID: Int?

    /// Called when a row’s status changes (optimistic handled by parent)
    let onChange: (_ gentID: Int, _ status: AvailabilityStatus) -> Void

    var body: some View {
        Card(header: "Availability") {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(allGents) { gent in
                    let status = dict[gent.id] ?? .no_reply

                    // Show thumbs if manager OR (gent mode AND this is me)
                    let showThumbs = canEditAll || (currentGentID == gent.id)
                    let thumbsAreEditable = showThumbs   // both manager and the signed-in gent can edit their thumbs

                    // Assign control visible for manager only
                    let showAssignControl = canEditAll

                    AvailabilityRow(
                        gent: gent,
                        status: status,
                        showThumbs: showThumbs,
                        thumbsEditable: thumbsAreEditable,
                        showAssignControl: showAssignControl,
                        onThumbUp: {
                            if status != .available { onChange(gent.id, .available) }
                            else { onChange(gent.id, .no_reply) }
                        },
                        onThumbDown: {
                            if status != .unavailable { onChange(gent.id, .unavailable) }
                            else { onChange(gent.id, .no_reply) }
                        },
                        onAssign: {
                            // Manager tap on circle moves available -> assigned
                            if status == .available {
                                onChange(gent.id, .assigned)
                            }
                        }
                    )
                }
            }
        }
    }

    private var dict: [Int: AvailabilityStatus] {
        Dictionary(uniqueKeysWithValues: availability.map { ($0.gent_id, $0.status) })
    }
}

private struct AvailabilityRow: View {
    let gent: Gent
    let status: AvailabilityStatus

    /// Whether thumbs are shown at all (manager OR “me” in gent mode)
    let showThumbs: Bool
    /// Whether the thumbs are enabled for tapping
    let thumbsEditable: Bool

    /// Manager’s assign control visibility
    let showAssignControl: Bool

    let onThumbUp: () -> Void
    let onThumbDown: () -> Void
    let onAssign: () -> Void

    var body: some View {
        HStack(spacing: 12) {

            // Thumbs (only shown for manager or "me" in gent mode)
            if showThumbs {
                HStack(spacing: 8) {
                    Button(action: onThumbUp) {
                        Image(systemName: status == .available ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!thumbsEditable)
                    .help("Available")

                    Button(action: onThumbDown) {
                        Image(systemName: status == .unavailable ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!thumbsEditable)
                    .help("Unavailable")
                }
            }

            // Name
            Text(gent.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Assign control (manager only):
            // - When .available → show a tappable empty circle to assign
            // - When .assigned  → show a *filled* checkmark that persists (non-tappable)
            if showAssignControl {
                if status == .available {
                    Button(action: onAssign) {
                        Image(systemName: "circle")            // empty circle before assigning
                    }
                    .buttonStyle(.borderless)
                    .help("Assign")
                } else if status == .assigned {
                    Image(systemName: "checkmark.circle.fill") // persists after assigned
                        .foregroundStyle(.blue)
                        .help("Assigned")
                }
            }

            // Status tag
            AvailabilityTag(status: status)
        }
        .padding(.vertical, 4)
        .opacity((showThumbs && thumbsEditable) || showAssignControl ? 1.0 : 0.9)
    }
}

private struct AvailabilityTag: View {
    let status: AvailabilityStatus
    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }
    private var bg: Color {
        switch status {
        case .no_reply:    return .gray.opacity(0.18)
        case .available:   return .green.opacity(0.18)
        case .unavailable: return .red.opacity(0.18)
        case .assigned:    return .blue.opacity(0.18)
        }
    }
    private var fg: Color {
        switch status {
        case .no_reply:    return .gray
        case .available:   return .green
        case .unavailable: return .red
        case .assigned:    return .blue
        }
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

struct PhaseBadge: View {
    let phase: Phase

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .accessibilityLabel("Phase \(label)")
    }

    private var label: String { phase.label }
    private var background: Color {
        switch phase {
        case .planning:  return Color.yellow.opacity(0.18)
        case .booked:    return Color.blue.opacity(0.18)
        case .completed: return Color.green.opacity(0.18)
        }
    }
    private var foreground: Color {
        switch phase {
        case .planning:  return .yellow
        case .booked:    return .blue
        case .completed: return .green
        }
    }
}
