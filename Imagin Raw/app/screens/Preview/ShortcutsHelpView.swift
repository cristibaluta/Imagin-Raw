//
//  ShortcutsHelpView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 02.02.2026.
//

import SwiftUI

struct ShortcutsHelpView: View {
    #if os(macOS)
    @ObservedObject private var store = ShortcutStore.shared
    #endif

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            // Header
            VStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                VStack(spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }

            HStack(alignment: .top, spacing: 30) {
                // col 1: fixed keys
                VStack(alignment: .leading) {
                    line("1 - 5", "Rating")
                    line("6 - 0", "Labels")
                    line("⌥ 1 - 5", "Filter by Rating")
                    line("⌥ 6 - 0", "Filter by Label")
                    line("⌥ X", "Filter by Rejected")
                    line("⌘ Z", "Undo Move to Trash")
                    line("Scroll", "Zoom closer/farther")
                }
                .frame(width: 260)

                // col 2: keys you can change in Settings > Shortcuts
                VStack(alignment: .leading) {
                    #if os(macOS)
                    ForEach(ShortcutAction.allCases, id: \.self) { action in
                        if let shortcut = store.shortcut(for: action) {
                            line(shortcut.displayName, action.title)
                        }
                    }
                    #endif
                }
                .frame(width: 260)
            }
            Text("Change shortcuts in Settings (⌘,) > Shortcuts. In Review Mode you can label & rate photos while you hover and press the keys.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private func line(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 0) {
            Text(keys)
                .frame(width: 80, alignment: .leading)
            Text(title)
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
    }
}
