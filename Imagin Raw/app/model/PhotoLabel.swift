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

enum PhotoLabel: String, CaseIterable {

    case noLabel = "No Label"
    case select = "Select"
    case second = "Second"
    case approved = "Approved"
    case review = "Review"
    case todo = "To Do"
    case rejected = "Rejected"

    var color: Color {
        switch self {
            case .select:   return .red
            case .second:   return .yellow
            case .approved: return Color(red: 133/255, green: 199/255, blue: 102/255)
            case .review:   return .blue
            case .todo:     return .purple
            case .rejected: return .orange
            default:        return .secondary
        }
    }

    var textColor: Color {
        switch self {
            case .second, .approved:                 return .black
            case .select, .review, .todo, .rejected: return .white
            default:                                 return .primary
        }
    }

#if os(macOS)
    var nsColor: NSColor {
        NSColor(self.color)
    }

    var nsCGColor: CGColor {
        nsColor.cgColor
    }

    var nsTextColor: NSColor {
        NSColor(textColor)
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
