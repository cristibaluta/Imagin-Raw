//
//  PhotoLabel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.05.2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Centralised label colour definitions.
/// All other files should call these instead of hardcoding colours.
enum PhotoLabel {

    // MARK: - SwiftUI colours (used in SwiftUI views and FilterPopoverView)

    static func color(for label: String) -> Color {
        switch label {
        case "Select":   return .red
        case "Second":   return .yellow
        case "Approved": return Color(red: 133/255, green: 199/255, blue: 102/255)
        case "Review":   return .blue
        case "To Do":    return .purple
        case "Rejected": return .orange
        default:         return .secondary
        }
    }

    static func textColor(for label: String) -> Color {
        switch label {
        case "Second", "Approved": return .black
        case "Select", "Review", "To Do", "Rejected": return .white
        default: return .primary
        }
    }

    // MARK: - AppKit colours (used in NSView-based cells)

#if os(macOS)
    static func nsColor(for label: String) -> NSColor {
        switch label {
        case "Select":   return .systemRed
        case "Second":   return .systemYellow
        case "Approved": return NSColor(red: 133/255, green: 199/255, blue: 102/255, alpha: 1)
        case "Review":   return .systemBlue
        case "To Do":    return .systemPurple
        case "Rejected": return .systemOrange
        default:         return .clear
        }
    }

    static func nsTextColor(for label: String) -> NSColor {
        switch label {
        case "Second", "Approved": return .black
        case "Select", "Review", "To Do", "Rejected": return .white
        default: return .labelColor
        }
    }
#endif

#if os(iOS)
    static func uiColor(for label: String) -> UIColor {
        switch label {
        case "Select":   return .systemRed
        case "Second":   return .systemYellow
        case "Approved": return UIColor(red: 133/255, green: 199/255, blue: 102/255, alpha: 1)
        case "Review":   return .systemBlue
        case "To Do":    return .systemPurple
        case "Rejected": return .systemOrange
        default:         return .clear
        }
    }

    static func uiTextColor(for label: String) -> UIColor {
        switch label {
        case "Second", "Approved": return .black
        case "Select", "Review", "To Do", "Rejected": return .white
        default: return .label
        }
    }
#endif
}
