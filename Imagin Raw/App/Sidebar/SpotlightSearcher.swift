//
//  SpotlightSearcher.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import Foundation
import AppKit

/// Uses NSMetadataQuery (Spotlight) to search for folders by name across the file system.
/// Results are scoped to the root folders the user has added to the sidebar.
@MainActor
class SpotlightSearcher: ObservableObject {

    @Published var results: [FolderItem] = []
    @Published var isSearching: Bool = false

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    deinit {
        query?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func search(query searchText: String, in rootFolders: [FolderItem]) {
        guard searchText.count >= 3 else {
            stopSearch()
            results = []
            return
        }

        stopSearch()
        isSearching = true
        results = []

        let metadataQuery = NSMetadataQuery()
        self.query = metadataQuery

        // Search for directories whose display name contains the search text
        metadataQuery.predicate = NSPredicate(
            format: "kMDItemContentType == 'public.folder' AND kMDItemDisplayName CONTAINS[cd] %@",
            searchText
        )

        // Scope the search to the user's added root folders only
        metadataQuery.searchScopes = rootFolders.map { $0.url.path as NSString }

        metadataQuery.sortDescriptors = [
            NSSortDescriptor(key: "kMDItemDisplayName", ascending: true)
        ]

        // Observe results
        let finishedObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery,
            queue: .main
        ) { [weak self] _ in
            self?.handleResults()
        }

        let updatedObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: metadataQuery,
            queue: .main
        ) { [weak self] _ in
            self?.handleResults()
        }

        observers = [finishedObserver, updatedObserver]

        metadataQuery.start()
    }

    func stopSearch() {
        query?.stop()
        query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        isSearching = false
    }

    private func handleResults() {
        guard let query else { return }

        query.disableUpdates()

        var folderItems: [FolderItem] = []
        for result in query.results {
            guard let metadataItem = result as? NSMetadataItem,
                  let path = metadataItem.value(forAttribute: kMDItemPath as String) as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path)
            // Leaf folder — no children loaded, tapping will load photos directly
            folderItems.append(FolderItem(url: url, children: nil))
        }

        results = folderItems
        isSearching = false

        query.enableUpdates()
    }
}
