//
//  ExternalAppManager.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 05.02.2026.
//

import Foundation
import AppKit

class ExternalAppManager {
    static let shared = ExternalAppManager()
    
    private init() {}
    
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