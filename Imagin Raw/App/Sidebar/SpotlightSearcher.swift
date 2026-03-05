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

    private var folderQuery: NSMetadataQuery?
    private var photoQuery: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    private let rawExtensions = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                                  "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                                  "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                                  "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d",
                                  "jpg", "jpeg", "png", "heic", "tiff", "tif"]

    deinit {
        folderQuery?.stop()
        photoQuery?.stop()
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

        let scopes = rootFolders.map { $0.url.path as NSString }
        startFolderQuery(searchText: searchText, scopes: scopes)
        startPhotoQuery(searchText: searchText, scopes: scopes)
    }

    func stopSearch() {
        folderQuery?.stop()
        folderQuery = nil
        photoQuery?.stop()
        photoQuery = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        isSearching = false
    }

    // MARK: - Private

    private func startFolderQuery(searchText: String, scopes: [NSString]) {
        let q = NSMetadataQuery()
        folderQuery = q
        q.predicate = NSPredicate(
            format: "kMDItemContentType == 'public.folder' AND kMDItemDisplayName CONTAINS[cd] %@",
            searchText
        )
        q.searchScopes = scopes
        q.sortDescriptors = [NSSortDescriptor(key: "kMDItemDisplayName", ascending: true)]

        let finished = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
        ) { [weak self] _ in self?.handleFolderResults() }
        let updated = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: q, queue: .main
        ) { [weak self] _ in self?.handleFolderResults() }
        observers += [finished, updated]
        q.start()
    }

    private func startPhotoQuery(searchText: String, scopes: [NSString]) {
        let q = NSMetadataQuery()
        photoQuery = q

        // Build a predicate that matches image files by display name
        let extensionPredicates = rawExtensions.map {
            NSPredicate(format: "kMDItemFSName ENDSWITH[cd] %@", ".\($0)")
        }
        let anyImageType = NSCompoundPredicate(orPredicateWithSubpredicates: extensionPredicates)
        let namePredicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", searchText)
        q.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [namePredicate, anyImageType])
        q.searchScopes = scopes
        q.sortDescriptors = [NSSortDescriptor(key: "kMDItemDisplayName", ascending: true)]

        let finished = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
        ) { [weak self] _ in self?.handlePhotoResults() }
        let updated = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: q, queue: .main
        ) { [weak self] _ in self?.handlePhotoResults() }
        observers += [finished, updated]
        q.start()
    }

    private func handleFolderResults() {
        guard let q = folderQuery else { return }
        q.disableUpdates()
        var folderItems: [FolderItem] = []
        for result in q.results {
            guard let item = result as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            folderItems.append(FolderItem(url: URL(fileURLWithPath: path), children: nil))
        }
        results = folderItems
        checkSearchDone()
        q.enableUpdates()
    }

    private func handlePhotoResults() {
        guard let q = photoQuery else { return }
        q.disableUpdates()
        var photos: [PhotoItem] = []
        for result in q.results {
            guard let item = result as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let date = (item.value(forAttribute: kMDItemFSCreationDate as String) as? Date) ?? Date()
            photos.append(PhotoItem(path: path, xmp: nil, dateCreated: date, hasACR: false, hasJPG: false, inCameraRating: nil))
        }
        photoResults = photos
        checkSearchDone()
        q.enableUpdates()
    }

    private func checkSearchDone() {
        // Mark search as done only once both queries have reported back
        let folderDone = !(folderQuery?.isGathering ?? true)
        let photoDone = !(photoQuery?.isGathering ?? true)
        if folderDone && photoDone {
            isSearching = false
        }
    }
}
