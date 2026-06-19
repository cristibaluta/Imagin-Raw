//
//  SettingsView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.05.2026.
//

import SwiftUI

#if os(macOS)
struct SettingsView: View {
    @State private var showResetConfirmation = false
    @State private var showCacheConfirmation = false
    @State private var cacheSize: String = "Calculating..."
    @State private var selectedTheme: String = appPrefs.string(.theme)

    var body: some View {
        VStack(spacing: 20) {

            // Theme
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appearance")
                        .font(.headline)
                }
                Spacer()
                Picker("", selection: $selectedTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: selectedTheme) { _, value in
                    appPrefs.set(value, forKey: .theme)
                    NotificationCenter.default.post(name: .colorSchemeDidChange, object: nil)
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reset All Preferences")
                        .font(.headline)
                }
                Spacer()
                Button("Reset") {
                    showResetConfirmation = true
                }
                .alert("Reset Preferences", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        resetAllPreferences()
                    }
                } message: {
                    Text("Are you sure? This will reset all settings to defaults.")
                }
            }

            // Delete Cache
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delete Thumbnail Cache")
                        .font(.headline)
                    Text("Current size: \(cacheSize). Thumbnails will be regenerated as needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Delete") {
                    showCacheConfirmation = true
                }
                .alert("Delete Cache", isPresented: $showCacheConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        deleteAllCache()
                    }
                } message: {
                    Text("Are you sure? All cached thumbnails will be deleted.")
                }
            }

            Divider()

            // Shortcuts
            ShortcutsHelpView()
        }
        .padding(30)
        .frame(width: 550)
        .onAppear {
            calculateCacheSize()
        }
    }

    // MARK: - Actions

    private func resetAllPreferences() {
        let preserved: Set<AppPreference> = [.userFolderBookmarks, .photoLibraryEnabled, .theme]
        for pref in AppPreference.allCases where !preserved.contains(pref) {
            appPrefs.reset(pref)
        }
        RCLog("All preferences reset to defaults (folders preserved)")
        NotificationCenter.default.post(name: .preferencesDidReset, object: nil)
    }

    private func deleteAllCache() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheRoot = cachesDir.appendingPathComponent("ro.imagin.raw")
        try? FileManager.default.removeItem(at: cacheRoot)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        cacheSize = "0 MB"
        RCLog("All cache deleted")
    }

    private func calculateCacheSize() {
        DispatchQueue.global(qos: .utility).async {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let cacheRoot = cachesDir.appendingPathComponent("ro.imagin.raw")
            let size = directorySize(at: cacheRoot)
            let formatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            DispatchQueue.main.async {
                cacheSize = formatted
            }
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
#endif
