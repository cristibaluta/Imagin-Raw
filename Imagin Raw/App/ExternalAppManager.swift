//
//  ExternalAppManager.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.02.2026.
//

import Foundation
import AppKit

class ExternalAppManager: ObservableObject {

    @Published var discoveredPhotoApps: [PhotoApp] = []

    private let selectedAppKey = "SelectedExternalApp"

    init() {}

    // MARK: - Photo App Discovery

    func loadPhotoApps(completion: @escaping () -> Void = {}) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.predicate = NSPredicate(
            format: "kMDItemContentTypeTree == 'com.apple.application-bundle'"
        )

        query.start()

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { _ in
            query.stop()

            // Keywords to identify photo editing applications
            let photoKeywords = [
                "lightroom", "photoshop", "After-Effects", "Premiere-Pro",
                "com.dxo", "captureone", "photoraw",
                ".luminar", "affinity", "pixelmator", "gimp", "sketch", "canva",
                ".on1.", "topaz", "nik", "hdr", "panorama", "preview"
            ]

            // Bundle IDs to ignore from the photo apps list
            let ignoredApps = [
                "com.apple.PreviewShell"
            ]

            var apps: [PhotoApp] = []

            for item in query.results {
                guard let mdItem = item as? NSMetadataItem,
                      let path = mdItem.value(forAttribute: kMDItemPath as String) as? String,
                      let bundle = Bundle(path: path),
                      let bundleID = bundle.bundleIdentifier
                else { continue }

                // Skip ignored apps
                if ignoredApps.contains(bundleID) {
                    continue
                }

                let name = bundle.object(
                    forInfoDictionaryKey: "CFBundleDisplayName"
                ) as? String
                ?? bundle.object(
                    forInfoDictionaryKey: "CFBundleName"
                ) as? String
                ?? (path as NSString).lastPathComponent

                // Check if app name contains photo-related keywords
                let appNameLowercased = bundleID.lowercased()
                let isPhotoApp = photoKeywords.contains { keyword in
                    appNameLowercased.contains(keyword)
                }

                if isPhotoApp {
                    let photoApp = PhotoApp(
                        name: name,
                        bundleIdentifier: bundleID,
                        url: URL(fileURLWithPath: path)
                    )
                    apps.append(photoApp)
                    print("Found compatible app: \(name) (bundle ID: \(bundleID))")
                }
            }

            // Sort apps by name and update the discovered apps list
            self.discoveredPhotoApps = apps.sorted { $0.name < $1.name }

            // Call completion handler
            completion()
        }
    }

    // MARK: - Selected App Management

    func saveSelectedApp(_ app: PhotoApp?) {
        if let app = app {
            UserDefaults.standard.set(app.bundleIdentifier, forKey: selectedAppKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedAppKey)
        }
    }

    func loadSelectedApp() -> PhotoApp? {
        guard let savedBundleID = UserDefaults.standard.string(forKey: selectedAppKey) else {
            return nil
        }

        // Find the app with matching bundle identifier from discovered apps
        return discoveredPhotoApps.first { $0.bundleIdentifier == savedBundleID }
    }

    // MARK: - Photo Opening

    /// Opens multiple photos in an external app or the default system app
    func openPhotos(_ photos: [PhotoItem], with selectedApp: PhotoApp?) {
        let urls = photos.map { URL(fileURLWithPath: $0.path) }

        guard !urls.isEmpty else { return }

        if let app = selectedApp {
            // Use the selected PhotoApp
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: configuration) { app, error in
                if let error = error {
                    print("Failed to open photos with \(selectedApp?.displayName ?? "selected app"): \(error)")
                    // Fallback to default application
                    self.openPhotosWithDefaultApp(urls)
                } else {
                    print("Opened \(urls.count) photos with \(selectedApp?.displayName ?? "selected app")")
                }
            }
        } else {
            // Use system default application
            openPhotosWithDefaultApp(urls)
        }
    }

    /// Opens a single photo in an external app or the default system app
    func openPhoto(_ photo: PhotoItem, with selectedApp: PhotoApp?) {
        openPhotos([photo], with: selectedApp)
    }

    private func openPhotosWithDefaultApp(_ urls: [URL]) {
        guard let firstURL = urls.first else { return }

        // Find the default application for the first file
        if let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: firstURL) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: defaultAppURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to open photos with default app: \(error)")
                } else {
                    print("Opened \(urls.count) photos with default app")
                }
            }
        } else {
            // Fallback - open each URL individually
            print("No default app found, opening \(urls.count) photos individually")
            for url in urls {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
