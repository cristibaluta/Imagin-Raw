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
            // Header
            VStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                VStack(spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text("Master these shortcuts to browse and organize photos efficiently")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Shortcuts sections
            VStack(spacing: 24) {
                // Navigation shortcuts
                ShortcutSection(
                    title: "Navigation",
                    icon: "arrow.left.arrow.right",
                    shortcuts: [
                        ("← → ↑ ↓", "Navigate between photos"),
                        ("Return", "Open photo in external app"),
                        ("Cmd+A", "Select all photos")
                    ]
                )

                // Labeling shortcuts - horizontal layout
                VStack(spacing: 12) {
                    // Section header
                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.accentColor)

                        Text("Photo Labeling")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()
                    }

                    // Color labels in a horizontal row
                    HStack(spacing: 12) {
                        ColoredKeyShortcut(key: "6", color: .red, label: "Select")
                        ColoredKeyShortcut(key: "7", color: .yellow, label: "Second")
                        ColoredKeyShortcut(key: "8", color: .green, label: "Approved")
                        ColoredKeyShortcut(key: "9", color: .blue, label: "Review")
                        ColoredKeyShortcut(key: "0", color: .purple, label: "To Do")
                    }

                    // Other shortcuts below
                    VStack(spacing: 8) {
                        HStack(spacing: 16) {
                            Text("-")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                                .frame(minWidth: 60, alignment: .center)

                            Text("Remove label")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)

                            Spacer()
                        }

                        HStack(spacing: 16) {
                            HStack(spacing: -6) {
                                Text("d")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                    .frame(minWidth: 60, alignment: .center)
                                Text("Delete")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                    .frame(minWidth: 60, alignment: .center)
                            }

                            Text("Mark for deletion")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(8)
            }

            Spacer()

            // Footer instruction
            VStack(spacing: 8) {
                Text("Select a photo from the thumbnails to start previewing")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Use Command+Click and Shift+Click to select multiple photos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ShortcutSection: View {
    let title: String
    let icon: String
    let shortcuts: [(key: String, description: String)]

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()
            }

            // Shortcuts list
            VStack(spacing: 8) {
                ForEach(shortcuts, id: \.key) { shortcut in
                    HStack(spacing: 16) {
                        // Key combination
                        Text(shortcut.key)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                            .frame(minWidth: 60, alignment: .center)

                        // Description
                        Text(shortcut.description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
}

struct ColoredKeyShortcut: View {
    let key: String
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            // Key with colored background
            Text(key)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color)
                .cornerRadius(6)
                .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 1)

            // Label text below
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
