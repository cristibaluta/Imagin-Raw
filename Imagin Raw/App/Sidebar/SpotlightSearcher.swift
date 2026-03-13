//
//  SpotlightSearcher.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import Foundation

/// Uses NSMetadataQuery (Spotlight) to search for folders and image files by name.
/// Results are scoped to the root folders the user has added to the sidebar.
@MainActor
class SpotlightSearcher: ObservableObject {

    @Published var results: [FolderItem] = []
    @Published var photoResults: [PhotoItem] = []
    @Published var isSearching: Bool = false

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private let backgroundQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

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

        let finished = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                                              object: q,
                                                              queue: backgroundQueue) { [weak self] notification in
            guard let q = notification.object as? NSMetadataQuery else { return }
            self?.handleResults(q)
        }
        let updated = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate,
                                                             object: q,
                                                             queue: backgroundQueue) { [weak self] notification in
            guard let q = notification.object as? NSMetadataQuery else { return }
            self?.handleResults(q)
        }
        observers = [finished, updated]
        q.start()
    }

    func stopSearch() {
        query?.stop()
        query = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        observers = []
        isSearching = false
    }

    nonisolated private func handleResults(_ q: NSMetadataQuery) {
        q.disableUpdates()

        let supportedExtensions = FilesExtensions.all
        var folderItems: [FolderItem] = []
        var photos: [PhotoItem] = []

        for result in q.results {
            #if os(macOS)
            guard let item = result as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let contentType = item.value(forAttribute: kMDItemContentType as String) as? String ?? ""
            if contentType == "public.folder" {
                folderItems.append(FolderItem(url: url, children: nil))
            } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                let date = (item.value(forAttribute: kMDItemFSCreationDate as String) as? Date) ?? Date()
                photos.append(PhotoItem(path: path, xmp: nil, dateCreated: date,
                                        hasACR: false, hasJPG: false, inCameraRating: nil))
            }
            #endif
        }

        let isStillGathering = q.isGathering
        q.enableUpdates()

        DispatchQueue.main.async { [weak self] in
            self?.results = folderItems
            self?.photoResults = photos
            self?.isSearching = isStillGathering
        }
    }
}
