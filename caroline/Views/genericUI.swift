//
//  genericUI.swift
//  caroline
//
//  Created by Alexander Weiss on 17/08/2025.
//

import SwiftUI

struct Card<Content: View>: View {
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
