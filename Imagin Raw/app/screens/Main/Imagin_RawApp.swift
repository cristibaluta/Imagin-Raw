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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color(NSColor(white: 0.2, alpha: 1.0)))
                .id(contentViewID)
                .onReceive(NotificationCenter.default.publisher(for: .preferencesDidReset)) { _ in
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
