//
//  ExternalAppManager.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 16.04.2026.
//

import Foundation

#if os(iOS)
class ExternalAppManager: ObservableObject {

    @Published var discoveredPhotoApps: [PhotoApp] = []
    @Published var selectedApp: PhotoApp?

    func openPhotos(_ photos: [PhotoItem]) {
    }
    func saveSelectedApp(_ app: PhotoApp?) {
    }
}
#endif
