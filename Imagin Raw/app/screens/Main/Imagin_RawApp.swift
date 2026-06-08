//
//  Imagin_BridgeApp.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 29.01.2026.
//

import SwiftUI

extension Notification.Name {
    static let preferencesDidReset = Notification.Name("preferencesDidReset")
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct ImaginRawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var contentViewID = UUID()
    @State private var theme: String = appPrefs.string(.theme)

    private var colorScheme: ColorScheme? {
        switch theme {
            case "light": return .light
            case "dark":  return .dark
            default:      return nil
        }
    }

    init() {
        #if !DEBUG
        disableTraces()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
                .background(Color(NSColor(white: colorScheme == .dark ? 0.25 : 0.85, alpha: 1.0)))
                .id(contentViewID)
                .onReceive(NotificationCenter.default.publisher(for: .preferencesDidReset)) { _ in
                    theme = appPrefs.string(.theme)
                    contentViewID = UUID()
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
        }
    }
}
#elseif os(iOS)
@main
struct ImaginRawApp: App {
//    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color(UIColor(white: 0.2, alpha: 1.0)))
        }
    }
}
#endif
