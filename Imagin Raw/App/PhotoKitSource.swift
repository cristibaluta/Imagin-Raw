//
//  PhotoKitSource.swift
//  Imagin Raw
//
//  Bridges the Photos library into the app's folder/photo model.
//  A PHAssetCollection maps to a FolderItem; PHAssets inside it become PhotoItems.
//

import Photos
import Foundation

// MARK: - Well-known virtual URL

extension URL {
    /// Sentinel URL used to represent the top-level "Photos Library" entry in the sidebar.
    static let photoLibraryRoot = URL(string: "imagin-raw://photos-library")!

    var isPhotoLibraryRoot: Bool { self == .photoLibraryRoot }
    var isPhotoKitAlbum: Bool { scheme == "imagin-raw" && host == "album" }

    static func photoKitAlbum(localIdentifier: String) -> URL {
        URL(string: "imagin-raw://album/\(localIdentifier)")!
    }

    var photoKitAlbumIdentifier: String? {
        guard isPhotoKitAlbum else { return nil }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - PhotoKitSource

enum PhotoKitSource {

    // MARK: Authorisation

    /// Requests authorisation if needed and calls back on the main queue.
    static func requestAuthorisation(completion: @escaping (Bool) -> Void) {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    completion(status == .authorized || status == .limited)
                }
            }
        default:
            completion(false)
        }
    }

    // MARK: Folder tree

    /// Builds the sidebar FolderItem tree for the Photos library:
    ///   📷 Photos Library
    ///       └── Smart Albums (Recents, Favourites, …)
    ///       └── User Albums
    ///       └── Shared Albums
    static func buildFolderTree() -> FolderItem {
        var children: [FolderItem] = []

        // Smart albums
        let smartResult = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        var smartChildren: [FolderItem] = []
        smartResult.enumerateObjects { collection, _, _ in
            guard collection.estimatedAssetCount > 0 || collection.assetCollectionSubtype == .smartAlbumUserLibrary else { return }
            smartChildren.append(FolderItem(url: .photoKitAlbum(localIdentifier: collection.localIdentifier),
                                            displayName: collection.localizedTitle ?? "Album"))
        }
        if !smartChildren.isEmpty {
            children.append(FolderItem(url: URL(string: "imagin-raw://smart-albums")!,
                                       children: smartChildren,
                                       displayName: "Smart Albums"))
        }

        // User albums
        let userResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var userChildren: [FolderItem] = []
        userResult.enumerateObjects { collection, _, _ in
            userChildren.append(FolderItem(url: .photoKitAlbum(localIdentifier: collection.localIdentifier),
                                           displayName: collection.localizedTitle ?? "Album"))
        }
        if !userChildren.isEmpty {
            children.append(FolderItem(url: URL(string: "imagin-raw://user-albums")!,
                                       children: smartChildren,
                                       displayName: "My Albums"))
        }

        return FolderItem(url: .photoLibraryRoot,
                          children: smartChildren,
                          displayName: "Photos Library")
    }

    // MARK: Photo loading

    /// Fetches all photos from a PHAssetCollection.
    /// For Recents / User Library we use no sort descriptor so PhotoKit returns
    /// assets in its native "recently added" order (oldest → newest), which
    /// matches exactly what the native Photos app shows.
    static func loadPhotos(albumIdentifier: String) -> [PhotoItem] {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil)
        guard let collection = collections.firstObject else {
            return []
        }

        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let subtype = collection.assetCollectionSubtype
        options.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(in: collection, options: nil)
        var items: [PhotoItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(asset: asset))
        }
        return items
    }

    /// Fetches all assets in the whole library in "recently added" order.
    static func loadAllPhotos() -> [PhotoItem] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        // No sort descriptor → native recently-added order
        let assets = PHAsset.fetchAssets(with: options)
        var items: [PhotoItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(asset: asset))
        }
        return items
    }
}
