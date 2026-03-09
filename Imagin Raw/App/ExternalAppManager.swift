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
    @Published var selectedApp: PhotoApp?

    init() {
        loadPhotoApps()
    }

    private func loadPhotoApps() {
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
                }
            }

            // Sort apps by name and update the discovered apps list
            self.discoveredPhotoApps = apps.sorted { $0.name < $1.name }

            self.selectedApp = self.loadSelectedApp()
        }
    }

    func saveSelectedApp(_ app: PhotoApp?) {
        appPrefs.set(app?.bundleIdentifier ?? "", forKey: .selectedExternalApp)
        selectedApp = loadSelectedApp()
    }

    private func loadSelectedApp() -> PhotoApp? {
        let savedBundleID = appPrefs.string(.selectedExternalApp)
        guard !savedBundleID.isEmpty else { return nil }
        return discoveredPhotoApps.first { $0.bundleIdentifier == savedBundleID }
    }

    /// Opens multiple photos in an external app or the default system app
    func openPhotos(_ photos: [PhotoItem]) {
        let urls = photos.map { URL(fileURLWithPath: $0.path) }

        guard !urls.isEmpty else { return }

        if let app = selectedApp {
            // Use the selected PhotoApp
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: configuration) { app, error in
                if let _ = error {
                    self.openPhotosWithDefaultApp(urls)
                }
            }
        } else {
            openPhotosWithDefaultApp(urls)
        }
    }

    private func openPhotosWithDefaultApp(_ urls: [URL]) {
        guard let firstURL = urls.first else { return }

        // Find the default application for the first file
        if let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: firstURL) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: defaultAppURL, configuration: configuration) { (app, error) in
                if let _ = error {
                } else {
                }
            }
        } else {
            // Fallback - open each URL individually
            for url in urls {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
