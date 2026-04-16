//
//  PhotoKitSource.swift
//  Imagin Raw
//
//  Bridges the Photos library into the app's folder/photo model.
//  A PHAssetCollection maps to a FolderItem; PHAssets inside it become PhotoItems.
//

import Foundation
import Photos
import CryptoKit

// MARK: - Well-known virtual URL

extension URL {
    /// Sentinel URL used to represent the top-level "Photos Library" entry in the sidebar.
    static let photoLibraryRoot = URL(string: "imagin-raw://photos-library")!

    var isPhotoLibraryRoot: Bool {
        self == .photoLibraryRoot
    }
    var isPhotoKitAlbum: Bool {
        scheme == "imagin-raw" && host == "album"
    }

    static func photoKitAlbum(localIdentifier: String) -> URL {
        URL(string: "imagin-raw://album/\(localIdentifier)")!
    }

    var photoKitAlbumIdentifier: String? {
        guard isPhotoKitAlbum else {
            return nil
        }
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

    static func loadPhotos(albumIdentifier: String, basic: Bool = false) -> [PhotoItem] {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil)
        guard let collection = collections.firstObject else {
            return []
        }
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let subtype = collection.assetCollectionSubtype
        let isRecents = subtype == .smartAlbumUserLibrary
                     || subtype == .smartAlbumRecentlyAdded
        if !isRecents {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        }
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        var items: [PhotoItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(asset: asset, basic: basic))
        }
        return items
    }

    static func loadAllPhotos(basic: Bool = false) -> [PhotoItem] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let assets = PHAsset.fetchAssets(with: options)
        var items: [PhotoItem] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            items.append(PhotoItem(asset: asset, basic: basic))
        }
        return items
    }
}

struct PhotoKitPhotoSource: PhotoSource {
    let asset: PHAsset
    /// The path stored on PhotoItem (localIdentifier[/filename]) used as cache key.
    let photoPath: String

    var cacheKey: String {
        let url = URL(fileURLWithPath: photoPath)
        let dirHash = sha256Prefix(url.deletingLastPathComponent().path)
        return "\(dirHash)_\(url.lastPathComponent)"
    }

    func loadThumbnail(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {
        let size = CGSize(width: targetSize * 2, height: targetSize * 2)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            guard let image else {
                return
            }
            completion(image)
        }
    }

    func loadPreview(targetSize: CGFloat, completion: @escaping (IRImage?) -> Void) {
        let size = CGSize(width: targetSize * 2, height: targetSize * 2)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let image, !degraded else {
                if image == nil {
                    completion(nil)
                }
                return
            }
            completion(image)
        }
    }

    func loadExif() async -> ExifInfo? {
        return await withCheckedContinuation { cont in
            let opts = PHContentEditingInputRequestOptions()
            opts.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: opts) { input, _ in
                guard let url = input?.fullSizeImageURL,
                      let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: ExifInfo.from(imageProperties: props))
            }
        }
    }

    private func sha256Prefix(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}
