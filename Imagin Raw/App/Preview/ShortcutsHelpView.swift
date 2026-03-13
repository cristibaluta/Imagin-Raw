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

            // Shortcuts sections
            VStack(spacing: 24) {
                // Labeling shortcuts - horizontal layout
                VStack(spacing: 12) {
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
                                .background(Color(IRColor.controlBackgroundColor))
                                .cornerRadius(4)
                                .frame(minWidth: 60, alignment: .center)

                            Text("Remove label")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)

                            Spacer()
                        }

                        HStack(spacing: 16) {
                            Text("X")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(IRColor.controlBackgroundColor))
                                .cornerRadius(4)
                                .frame(minWidth: 60, alignment: .center)
                            Text("Reject (mark for deletion)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        HStack(spacing: 16) {
                            Text("⌘ Delete")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(IRColor.controlBackgroundColor))
                                .cornerRadius(4)
                                .frame(minWidth: 60, alignment: .center)
                            Text("Move to trash immediately")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(IRColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(IRColor.windowBackgroundColor))
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
