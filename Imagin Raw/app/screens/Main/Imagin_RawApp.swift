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

extension Notification.Name {
    static let colorSchemeDidChange = Notification.Name("colorSchemeDidChange")
}

extension Notification.Name {
    static let didOpenPhotos = Notification.Name("didOpenPhotos")
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        // Called with ALL dropped/opened files in one batch — use this
        // instead of onOpenURL when you need them together (e.g. to
        // populate a PhotoItem array as one collection view).
        RCLog("Trying to open URLs: \(urls)")
        NotificationCenter.default.post(name: .didOpenPhotos, object: urls)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Dock icon click with no windows open — let AppKit show the existing one.
        return true
    }
}

@main
struct ImaginRawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var contentViewID = UUID()
    @State private var theme: String = appPrefs.string(.theme)
//    @State private var colorScheme: ColorScheme?

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
                .background(Color.adaptive(light: NSColor(white: 0.85, alpha: 1.0),
                                           dark: NSColor(white: 0.25, alpha: 1.0),
                                           colorScheme: colorScheme))
                .id(contentViewID)
                .onReceive(NotificationCenter.default.publisher(for: .preferencesDidReset)) { _ in
                    theme = appPrefs.string(.theme)
                    contentViewID = UUID()
                }
                .onReceive(NotificationCenter.default.publisher(for: .colorSchemeDidChange)) { _ in
                    theme = appPrefs.string(.theme)
                    contentViewID = UUID()
                }
//                .onOpenURL { url in
//                    RCLog("Trying to open URL: \(url)")
//                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
//        .handlesExternalEvents(matching: ["*"])

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
