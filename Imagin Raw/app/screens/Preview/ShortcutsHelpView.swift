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
                        .foregroundColor(.primary)
                    Text("6 - 0   Labels")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("A       Approve Label")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("-       Remove Label")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .frame(width: 200)

                // col 2
                VStack(alignment: .leading) {
                    Text("Z       Zoom in/out")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("X       Mark for deletion")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("⌘ Del   Move to trash")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text("Space   Review mode")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .frame(width: 260)
            }
            Text("Note: In Review mode you can press the keys after you hover a photo, no need to click on it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
