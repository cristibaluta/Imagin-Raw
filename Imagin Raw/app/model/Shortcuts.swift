//
//  Shortcuts.swift
//  Imagin Raw
//
//  Keyboard shortcuts the user can change in Settings > Shortcuts.
//  Fixed keys (arrows, Return, 1-0 for ratings/labels, ⌘A, ⌘Z, ⌥ filters) are not listed here.
//

#if os(macOS)
import AppKit
import SwiftUI

/// An action that can be bound to a key.
enum ShortcutAction: String, CaseIterable, Codable {
    case approve
    case reject
    case moveToTrash
    case markForCopy
    case removeLabels
    case quickCopy
    case zoom
    case review
    case reviewFullScreen
    case toggleSidebar
    case toggleGridType

    var title: String {
        switch self {
            case .approve:          return "Approve"
            case .reject:           return "Reject"
            case .moveToTrash:      return "Move to Trash"
            case .markForCopy:      return "Mark for Copy"
            case .removeLabels:     return "Remove Label & Rating"
            case .quickCopy:        return "Quick Copy"
            case .zoom:             return "Zoom In/Out"
            case .review:           return "Review Mode"
            case .reviewFullScreen: return "Review Full Screen"
            case .toggleSidebar:    return "Toggle Sidebar"
            case .toggleGridType:   return "Toggle Grid Type"
        }
    }

    var defaultShortcut: KeyShortcut {
        switch self {
            case .approve:          return KeyShortcut(key: "a")
            case .reject:           return KeyShortcut(key: "x")
            case .moveToTrash:      return KeyShortcut(key: KeyShortcut.deleteKey, command: true)
            case .markForCopy:      return KeyShortcut(key: "c")
            case .removeLabels:     return KeyShortcut(key: "-")
            case .quickCopy:        return KeyShortcut(key: "c", option: true)
            case .zoom:             return KeyShortcut(key: "z")
            case .review:           return KeyShortcut(key: KeyShortcut.spaceKey)
            case .reviewFullScreen: return KeyShortcut(key: "f")
            case .toggleSidebar:    return KeyShortcut(key: "s")
            case .toggleGridType:   return KeyShortcut(key: "g")
        }
    }
}

/// A key plus modifiers. `key` is a lowercase character or one of the named keys below.
struct KeyShortcut: Codable, Equatable, Hashable {
    static let deleteKey = "delete"
    static let forwardDeleteKey = "forwardDelete"
    static let spaceKey = "space"
    static let tabKey = "tab"

    var key: String
    var command = false
    var option = false
    var control = false
    var shift = false

    /// Builds a shortcut from a key press. Returns nil for keys that can't be assigned
    /// (arrows, Return, Escape, function keys...).
    init?(event: NSEvent) {
        switch event.keyCode {
            case 51:  key = Self.deleteKey
            case 117: key = Self.forwardDeleteKey
            case 49:  key = Self.spaceKey
            case 48:  key = Self.tabKey
            case 36, 76, 53, 123, 124, 125, 126: return nil   // Return, Enter, Escape, arrows
            default:
                guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                      chars.count == 1,
                      let scalar = chars.unicodeScalars.first,
                      scalar.value < 0xF700 else {   // 0xF700... are function / navigation keys
                    return nil
                }
                key = chars
        }
        let flags = event.modifierFlags
        command = flags.contains(.command)
        option = flags.contains(.option)
        control = flags.contains(.control)
        shift = flags.contains(.shift)
    }

    init(key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.key = key
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// Text like "⌘⌫" or "⌥C".
    var displayName: String {
        var text = ""
        if control { text += "⌃" }
        if option  { text += "⌥" }
        if shift   { text += "⇧" }
        if command { text += "⌘" }
        switch key {
            case Self.deleteKey:        text += "⌫"
            case Self.forwardDeleteKey: text += "⌦"
            case Self.spaceKey:         text += "Space"
            case Self.tabKey:           text += "Tab"
            default:                    text += key.uppercased()
        }
        return text
    }

    /// Why this shortcut can't be used, or nil when it's fine.
    var reservedReason: String? {
        let noModifiers = !command && !option && !control
        if noModifiers && !shift, let digit = Int(key), (0...9).contains(digit) {
            return "1–0 set ratings and labels."
        }
        if option && !command && !control && !shift, Int(key) != nil || key == "x" {
            return "⌥ with numbers or X filters photos."
        }
        if command && !option && !control && !shift && (key == "a" || key == "z") {
            return key == "a" ? "⌘A selects all photos." : "⌘Z undoes Move to Trash."
        }
        if command, menuUses(self) {
            return "\(displayName) is already used by a menu command."
        }
        return nil
    }

    private func menuUses(_ shortcut: KeyShortcut) -> Bool {
        func search(_ menu: NSMenu) -> Bool {
            for item in menu.items {
                if let sub = item.submenu, search(sub) {
                    return true
                }
                guard !item.keyEquivalent.isEmpty else {
                    continue
                }
                let mask = item.keyEquivalentModifierMask
                let equivalent = item.keyEquivalent
                // An uppercase key equivalent implies Shift
                let impliedShift = equivalent != equivalent.lowercased()
                let matchesKey: Bool
                switch shortcut.key {
                    case Self.deleteKey:        matchesKey = equivalent == "\u{8}" || equivalent == "\u{7F}"
                    case Self.forwardDeleteKey: matchesKey = equivalent == "\u{F728}"
                    case Self.spaceKey:         matchesKey = equivalent == " "
                    case Self.tabKey:           matchesKey = equivalent == "\t"
                    default:                    matchesKey = equivalent.lowercased() == shortcut.key
                }
                if matchesKey,
                   mask.contains(.command) == shortcut.command,
                   mask.contains(.option) == shortcut.option,
                   mask.contains(.control) == shortcut.control,
                   (mask.contains(.shift) || impliedShift) == shortcut.shift {
                    return true
                }
            }
            return false
        }
        guard let menu = NSApp.mainMenu else {
            return false
        }
        return search(menu)
    }
}

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("ro.imagin.raw.shortcutsDidChange")
}

/// The current shortcuts. Only changes from the defaults are saved.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    /// nil value = the user removed the shortcut for that action.
    @Published private(set) var overrides: [ShortcutAction: KeyShortcut?] = [:]

    private init() {
        load()
        NotificationCenter.default.addObserver(forName: .preferencesDidReset, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.load()
            }
        }
    }

    func shortcut(for action: ShortcutAction) -> KeyShortcut? {
        if let override = overrides[action] {
            return override
        }
        return action.defaultShortcut
    }

    /// The action bound to the key press, if any.
    func action(for event: NSEvent) -> ShortcutAction? {
        guard let pressed = KeyShortcut(event: event) else {
            return nil
        }
        return ShortcutAction.allCases.first { shortcut(for: $0) == pressed }
    }

    /// Binds `shortcut` to `action`. Any other action using the same keys loses its shortcut.
    /// Returns the actions that lost it.
    @discardableResult
    func set(_ shortcut: KeyShortcut?, for action: ShortcutAction) -> [ShortcutAction] {
        var cleared: [ShortcutAction] = []
        if let shortcut {
            for other in ShortcutAction.allCases where other != action && self.shortcut(for: other) == shortcut {
                store(nil, for: other)
                cleared.append(other)
            }
        }
        store(shortcut, for: action)
        save()
        return cleared
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    var hasChanges: Bool {
        !overrides.isEmpty
    }

    private func store(_ shortcut: KeyShortcut?, for action: ShortcutAction) {
        if shortcut == action.defaultShortcut {
            overrides.removeValue(forKey: action)
        } else {
            overrides[action] = .some(shortcut)
        }
    }

    // MARK: - Saving (JSON string in preferences; a null shortcut marks a removed one)

    private struct Saved: Codable {
        var action: ShortcutAction
        var shortcut: KeyShortcut?
    }

    private func load() {
        let json = appPrefs.string(.customShortcuts)
        guard let data = json.data(using: .utf8),
              let saved = try? JSONDecoder().decode([Saved].self, from: data) else {
            overrides = [:]
            return
        }
        var result: [ShortcutAction: KeyShortcut?] = [:]
        for entry in saved {
            result[entry.action] = .some(entry.shortcut)
        }
        overrides = result
    }

    private func save() {
        let saved = overrides.map { Saved(action: $0.key, shortcut: $0.value) }
        if let data = try? JSONEncoder().encode(saved), let json = String(data: data, encoding: .utf8) {
            appPrefs.set(json, forKey: .customShortcuts)
        }
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }
}
#endif
