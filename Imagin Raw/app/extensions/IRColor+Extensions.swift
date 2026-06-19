//
//  IRColor+Extensions.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 13.03.2026.
//

#if os(iOS)
import UIKit

// Colors available on macOS but not on iOS
extension UIColor {
    static var windowBackgroundColor: UIColor {
        return .gray
    }
    static var controlBackgroundColor: UIColor {
        return .gray
    }
    static var textBackgroundColor: UIColor {
        return .systemBackground
    }
    static var underPageBackgroundColor: UIColor {
        .systemBackground
    }
}
#endif

import SwiftUI

extension Color {
    static func adaptive(light: NSColor, dark: NSColor, colorScheme: ColorScheme?) -> Color {
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
