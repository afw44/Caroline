//
//  GigDetailView.swift
//  giggle2
//
//  Created by Alexander Weiss on 14/08/2025.
//

import SwiftUI

struct GigDetailView: View {
    let role: UserRole
    @State var gig: Gig
    var onSaved: (() -> Void)? = nil

    // --- Edit mode state (manager only) ---
    @State private var isEditing = false
    @State private var dateText = ""
    @State private var clientEmail = ""
    @State private var feePounds = ""
    @State private var notesText = "my car is too far"
    @State private var isSaving = false
    @State private var errorMessage: String?
    var startInEdit: Bool = false          // <—


    // If you also show team here, keep your state for it:

    
    
    var body: some View {
        
        
        Form {
                    Section("Details") {
                        detailsSectionContent
                    }
                }
                .navigationTitle("Gig")
                

            // If you also show “Team”, keep that Section here…
        
        .navigationTitle("Gig")
        .toolbar {
            if role == .manager {
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        HStack(spacing: 8) {
                            Button("Cancel") { cancelEdit() }
                            Button("Save")   { Task { await saveEdits() } }
                                .disabled(!canSave)
                        }
                    } else {
                        Button("Edit") { beginEdit() }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = errorMessage {
                Text(msg)
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 8)
            }
        }
        
    }

    // MARK: - Section content (fixes the builder error)
    @ViewBuilder
    private var detailsSectionContent: some View {
        
        if role == .manager && isEditing {
            TextField("Date (YYYY-MM-DD)", text: $dateText)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())

            TextField("Client Email", text: $clientEmail)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            TextField("Fee (GBP)", text: $feePounds)
                .textFieldStyle(.roundedBorder)
            
            TextField("Notes", text: $notesText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
            
            gent_picker
            
        } else {
            LabeledContent("Date") { Text(gig.date) }
            LabeledContent("Client") { Text(gig.client_email) }
            LabeledContent("Fee") { Text(formatCurrencyCents(gig.fee)).monospaced() }
            LabeledContent("Notes") { Text(gig.notes?.isEmpty == false ? (gig.notes ?? "") : "—") }
        }
    }

    
    private var gent_picker: some View {
        
        List {
            ForEach(ALL_GENTS, id: \.self) { gent in
                Button {
                    toggle(gent)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: gig.assigned_ids.contains(gent.id) ? "checkmark.square.fill" : "square")
                            .imageScale(.large)
                        Text(gent.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ gent: Gent) {
        if let idx = gig.assigned_ids.firstIndex(of: gent.id) {
            gig.assigned_ids.remove(at: idx)
        } else {
            gig.assigned_ids.append(gent.id)
        }
    }
    
    // MARK: - Edit flow
    private func beginEdit() {
        dateText = gig.date
        clientEmail = gig.client_email
        feePounds = String(format: "%.2f", Double(gig.fee) / 100.0)
        notesText = gig.notes ?? ""     // ← seed
        errorMessage = nil
        isEditing = true
    }

    private func cancelEdit() {
        isEditing = false
        errorMessage = nil
    }

    private var canSave: Bool {
        !dateText.trimmingCharacters(in: .whitespaces).isEmpty &&
        !clientEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Decimal(string: feePounds) != nil)
    }

    
    @MainActor
    private func setError(_ message: String) {
        self.errorMessage = message
    }

    private func saveEdits() async {

        var patch = GigPatch()

        if dateText != gig.date { patch.date = dateText }
        if clientEmail != gig.client_email { patch.client_email = clientEmail }

        if let feeDec = Decimal(string: feePounds) {
            let cents = NSDecimalNumber(decimal: feeDec * 100).intValue
            if cents != gig.fee { patch.fee = cents }
        }

        if notesText != (gig.notes ?? "") {
            patch.notes = notesText
        }

        // Include assigned_ids only if changed (compare as Sets to ignore ordering)
        patch.assigned_ids = gig.assigned_ids
    

        // Nothing changed?
        if patch.date == nil,
           patch.client_email == nil,
           patch.fee == nil,
           patch.notes == nil,
           patch.assigned_ids == nil
        {
            isEditing = false
            return
        }

        guard let url = URL(string: "\(BASE_HTTP)/gigs/\(gig.id)") else {
            await setError("Invalid URL.")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let encoder = JSONEncoder()            // keep snake_case keys as-is
            req.httpBody = try encoder.encode(patch)

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

            #if DEBUG
            print("PATCH status:", http.statusCode)
            print("PATCH body:", String(data: data, encoding: .utf8) ?? "<non-UTF8 or empty>")
            #endif

            guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }

            // If server ever returns 204 or an empty body, just end cleanly.
            if data.isEmpty {
                await MainActor.run {
                    self.isEditing = false
                    self.errorMessage = nil
                    self.onSaved?()
                }
                return
            }

            let updated = try JSONDecoder().decode(Gig.self, from: data)
            
            
            await MainActor.run {
                self.gig = updated
                self.isEditing = false
                self.errorMessage = nil
                self.onSaved?()  // e.g. ask parent to refresh list if needed
            }
        } catch let encErr as EncodingError {
            await setError("Couldn’t prepare request (encoding error).")
            #if DEBUG
            print("EncodingError:", encErr)
            #endif
        } catch let decErr as DecodingError {
            await setError("Saved, but couldn’t read server response.")
            #if DEBUG
            print("DecodingError:", decErr, String(data: (try? JSONEncoder().encode(patch)) ?? Data(), encoding: .utf8) ?? "")
            #endif
        } catch {
            await setError("Couldn’t save changes. Check fields and try again.")
            #if DEBUG
            print("Save error:", error)
            #endif
        }
    }

    // MARK: - Utils
    private func formatCurrencyCents(_ cents: Int) -> String {
        let pounds = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "GBP"
        return f.string(from: NSNumber(value: pounds)) ?? "£\(pounds)"
    }
}

struct GigPatch: Encodable {
    var date: String?
    var client_email: String?
    var fee: Int?
    var notes: String?
    var assigned_ids: [Int]?
}


/// Simple wrapping HStack for tags
struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                content()
                    .fixedSize()
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > geo.size.width) {
                            width = 0
                            height -= d.height + spacing
                        }
                        let result = width
                        width -= d.width + spacing
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        return result
                    }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GigRow: View {
    let gig: Gig
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Date: \(gig.date)").font(.headline)
            HStack {
                Text("Client: \(gig.client_email)")
                Spacer()
                Text(currency(gig.fee)).monospaced()
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
    private func currency(_ cents: Int) -> String {
        let pounds = Double(cents) / 100.0
        return String(format: "£%.2f", pounds)
    }
}

struct ContentPlaceholder: View {
    var title: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.and.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


