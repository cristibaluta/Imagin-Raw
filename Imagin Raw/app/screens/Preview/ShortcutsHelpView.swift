//
//  ShortcutsHelpView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 02.02.2026.
//

import SwiftUI

struct ShortcutsHelpView: View {
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
                // col 1
                VStack(alignment: .leading) {
                    Text("1 - 5   Rating")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("6 - 0   Labels")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("-       Remove Label")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(" ")
                    Text("A       Approve")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("X       Reject")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .frame(width: 200)

                // col 2
                VStack(alignment: .leading) {
                    Text("⌥ 1 - 5 Filter by Rating")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("⌥ 6 - 0 Filter by Label")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("⌥ X     Filter by Rejected")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("⌘ Del   Move to Trash")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("⌘ Z     Undo Move to Trash")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("Z       Zoom in/out")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("Space   Review mode")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("C       Toggle Sidebar")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("G       Toggle Grid type")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .frame(width: 260)
            }
            Text("Note: In Review Mode you can label and rate photos while you hover.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}
