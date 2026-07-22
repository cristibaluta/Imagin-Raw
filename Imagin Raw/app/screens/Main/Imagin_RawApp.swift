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

extension Notification.Name {
    static let openNewWindow = Notification.Name("openNewWindow")
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        // Called with ALL dropped/opened files in one batch.
        RCLog("Open urls: \(urls.map(\.lastPathComponent))")
        // Store for windows that haven't appeared yet, then also notify existing windows.
        if let url = urls.first {
            AppState.pendingOpenURL = url
        }
        NotificationCenter.default.post(name: .didOpenPhotos, object: urls)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NotificationCenter.default.post(name: .openNewWindow, object: nil)
        }
        return true
    }
    func application(_ app: NSApplication, willEncodeRestorableState coder: NSCoder) {
        // no-op — nothing to preserve
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    // TODO: I don't think this is working
    // This is called by NSResponder.newWindowForTab(_:) going up the responder chain.
    // AppKit calls it when the user uses Cmd+T or the tab bar + button.
    @MainActor @objc func newWindowForTab(_ sender: Any?) {
        // Ask SwiftUI to open a new window, then immediately reparent it as a tab.
        // We capture the current key window first so we can add the tab to it.
        guard let currentWindow = NSApp.keyWindow else {
            return
        }
        openNewWindowHandler?()
        // The newest visible non-current window is the one SwiftUI just created.
        if let newWindow = NSApp.windows.first(where: { $0 !== currentWindow && !$0.isMiniaturized && $0.isVisible && $0.contentViewController != nil }) {
            currentWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }

    /// Set by ImaginRawApp to trigger openWindow without going through NotificationCenter.
    var openNewWindowHandler: (() -> Void)?
}

struct ImaginRawSession: Identifiable, Codable, Hashable {
    let id: UUID
    var rootURL: URL
}

@main
struct ImaginRawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var contentViewID = UUID()
    @State private var theme: String = appPrefs.string(.theme)
    @Environment(\.openWindow) private var openWindow

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
        WindowGroup(for: ImaginRawSession.ID.self) { $sessionID in
            ContentView(sessionID: sessionID)
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
                .onReceive(NotificationCenter.default.publisher(for: .openNewWindow)) { _ in
                    openWindow(value: UUID())
                }
                .onAppear {
                    // Give AppDelegate a direct handle to openWindow so newWindowForTab
                    // can call it without going through NotificationCenter (which would
                    // fire on every open ContentView and create multiple windows).
                    appDelegate.openNewWindowHandler = {
                        openWindow(value: UUID())
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
//        .commands {
//            CommandGroup(after: .newItem) {
//                Button("New Tab") {
//                    NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
//                }
//                .keyboardShortcut("t", modifiers: .command)
//            }
//        }

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
