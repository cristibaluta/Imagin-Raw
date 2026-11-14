//
//  ShortcutsSettingsView.swift
//  Imagin Raw
//
//  Settings > Shortcuts: click a shortcut, then press the new keys.
//

#if os(macOS)
import SwiftUI
import AppKit

struct ShortcutsSettingsView: View {
    @ObservedObject private var store = ShortcutStore.shared
    @State private var recording: ShortcutAction?
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click a shortcut, then press the new keys. Esc cancels.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { index, action in
                    row(for: action)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(index.isMultiple(of: 2) ? Color.secondary.opacity(0.06) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

            Text(message ?? " ")
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top) {
                Text("Fixed keys: arrows move, Return opens, 1–5 rate, 6–0 label, ⌥ + 1–0 or X filter, ⌘A select all, ⌘Z undo Move to Trash, Delete rejects.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Restore Defaults") {
                    stopRecording()
                    store.resetAll()
                    message = nil
                }
                .disabled(!store.hasChanges)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    @ViewBuilder
    private func row(for action: ShortcutAction) -> some View {
        HStack {
            Text(action.title)
            Spacer()
            Button {
                if recording == action {
                    stopRecording()
                } else {
                    startRecording(action)
                }
            } label: {
                Text(label(for: action))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(recording == action ? .accentColor : .primary)
                    .frame(minWidth: 90)
            }
            .help("Click, then press the new keys")

            Button {
                stopRecording()
                store.set(nil, for: action)
                message = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove this shortcut")
            .opacity(store.shortcut(for: action) == nil ? 0 : 1)
            .disabled(store.shortcut(for: action) == nil)
        }
    }

    private func label(for action: ShortcutAction) -> String {
        if recording == action {
            return "Press keys…"
        }
        return store.shortcut(for: action)?.displayName ?? "None"
    }

    // MARK: - Recording

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                handle(event)
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = nil
    }

    private func handle(_ event: NSEvent) {
        guard let action = recording else {
            return
        }
        if event.keyCode == 53 {   // Escape
            stopRecording()
            return
        }
        guard let shortcut = KeyShortcut(event: event) else {
            message = "That key can't be used. Try a letter, number or symbol, Space, Tab or Delete."
            return
        }
        if let reason = shortcut.reservedReason {
            message = "\(shortcut.displayName) can't be used: \(reason)"
            return
        }
        let cleared = store.set(shortcut, for: action)
        stopRecording()
        if cleared.isEmpty {
            message = nil
        } else {
            let names = cleared.map(\.title).joined(separator: ", ")
            message = "\(shortcut.displayName) was used by \(names), which now has no shortcut."
        }
    }
}
#endif
