//
//  ShortcutsHelpView.swift
//  Bridge Replacement
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
                        ("←→↑↓", "Navigate between photos"),
                        ("Return", "Open photo in external app"),
                        ("Cmd+A", "Select all photos")
                    ]
                )
                
                // Labeling shortcuts
                ShortcutSection(
                    title: "Photo Labeling",
                    icon: "tag",
                    shortcuts: [
                        ("6", "Select (Red label)"),
                        ("7", "Second (Yellow label)"),
                        ("8", "Approved (Green label)"),
                        ("9", "Review (Blue label)"),
                        ("0", "To Do (Purple label)"),
                        ("-", "Remove label"),
                        ("Delete", "Mark for deletion")
                    ]
                )
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

#Preview {
    ShortcutsHelpView()
        .frame(width: 600, height: 800)
}
