//
//  AppTheme.swift
//  Imagin Raw
//
//  The app's appearance: Light, Darker (Spotify-like) or Black.
//  Stored in the `theme` preference.
//

#if os(macOS)
import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable {
    case light
    case darker
    case black

    /// Reads the saved theme. Values from older versions ("system", "dark") become Darker.
    static var current: AppTheme {
        AppTheme(rawValue: appPrefs.string(.theme)) ?? .darker
    }

    var title: String {
        switch self {
            case .light:  return "Light"
            case .darker: return "Darker"
            case .black:  return "Black"
        }
    }

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

enum ThemeColors {

    /// Uses `light` in Light appearance, otherwise a gray of the given brightness
    /// (0 = black, 1 = white) for the current dark theme. Resolved at draw time.
    private static func color(light: NSColor, darker: CGFloat, black: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            guard appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua else { return light }
            return NSColor(white: AppTheme.current == .black ? black : darker, alpha: 1)
        }
    }

    /// Main window background (behind the thumbnail grid and preview).
    static var mainBackground: Color {
        Color(color(light: NSColor(white: 0.85, alpha: 1),
                    darker: 18/255,     // #121212
                    black: 0.0))
    }

    /// Folders sidebar.
    static var sidebarBackground: Color {
        Color(color(light: .underPageBackgroundColor,
                    darker: 0.0,        // #000000
                    black: 0.0))
    }

    /// Panels, popovers and fields that used the system window color.
    static var panelBackground: Color {
        Color(color(light: .windowBackgroundColor,
                    darker: 36/255,     // #242424
                    black: 24/255))
    }

    /// Background of a photo card in Review.
    static var reviewCardBackground: Color {
        Color(color(light: NSColor(white: 41/255, alpha: 1),
                    darker: 24/255,     // #181818
                    black: 0.0))
    }

    /// Thumbnail cell background in the grid.
    static func thumbCellBackground(isDark: Bool) -> NSColor {
        guard isDark else { return NSColor(white: 0.65, alpha: 1) }
        return AppTheme.current == .black
            ? NSColor(white: 12/255, alpha: 1)
            : NSColor(white: 24/255, alpha: 1)   // #181818
    }
}
#elseif os(iOS)
import SwiftUI
import UIKit

// iOS keeps its original colors.
enum ThemeColors {
    static var mainBackground: Color { Color(UIColor.windowBackgroundColor) }
    static var sidebarBackground: Color { Color(UIColor.underPageBackgroundColor) }
    static var panelBackground: Color { Color(UIColor.windowBackgroundColor) }
    static var reviewCardBackground: Color { Color(red: 41/255, green: 41/255, blue: 41/255) }
}
#endif
