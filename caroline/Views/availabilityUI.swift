//
//  availabilityUI.swift
//  caroline
//
//  Created by Alexander Weiss on 17/08/2025.
//

import SwiftUI

 struct AvailabilityTag: View {
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


// MARK: - Availability Card
struct AvailabilityCard: View {
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

struct AvailabilityRow: View {
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

