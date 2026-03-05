//
//  SpotlightSearcher.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import Foundation
import AppKit

/// Uses NSMetadataQuery (Spotlight) to search for folders and image files by name.
/// Results are scoped to the root folders the user has added to the sidebar.
@MainActor
class SpotlightSearcher: ObservableObject {

    @Published var results: [FolderItem] = []
    @Published var photoResults: [PhotoItem] = []
    @Published var isSearching: Bool = false

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    private let imageExtensions: Set<String> = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                                                 "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                                                 "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                                                 "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d",
                                                 "jpg", "jpeg", "png", "heic", "tiff", "tif"]

    deinit {
        query?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func search(query searchText: String, in rootFolders: [FolderItem]) {
        guard searchText.count >= 3 else {
            stopSearch()
            results = []
            photoResults = []
            return
        }

        stopSearch()
        isSearching = true
        results = []
        photoResults = []

        let q = NSMetadataQuery()
        self.query = q

        // Single predicate: match display name — folders and image files alike
        q.predicate = NSPredicate(
            format: "kMDItemDisplayName CONTAINS[cd] %@", searchText
        )
        q.searchScopes = rootFolders.map { $0.url.path as NSString }
        q.sortDescriptors = [NSSortDescriptor(key: "kMDItemDisplayName", ascending: true)]

        let finished = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
        ) { [weak self] _ in self?.handleResults() }
        let updated = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: q, queue: .main
        ) { [weak self] _ in self?.handleResults() }
        observers = [finished, updated]
        q.start()
    }

    func stopSearch() {
        query?.stop()
        query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        isSearching = false
    }

    private func handleResults() {
        guard let q = query else { return }
        q.disableUpdates()

        var folderItems: [FolderItem] = []
        var photos: [PhotoItem] = []

        for result in q.results {
            guard let item = result as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }

            let url = URL(fileURLWithPath: path)
            let contentType = item.value(forAttribute: kMDItemContentType as String) as? String ?? ""

            if contentType == "public.folder" {
                folderItems.append(FolderItem(url: url, children: nil))
            } else if imageExtensions.contains(url.pathExtension.lowercased()) {
                let date = (item.value(forAttribute: kMDItemFSCreationDate as String) as? Date) ?? Date()
                photos.append(PhotoItem(path: path, xmp: nil, dateCreated: date, hasACR: false, hasJPG: false, inCameraRating: nil))
            }
        }

        results = folderItems
        photoResults = photos
        isSearching = !(query?.isGathering == false)

        q.enableUpdates()
    }
}
