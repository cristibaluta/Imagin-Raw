//
//  SpotlightSearch.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05.03.2026.
//

import Foundation

final class SpotlightSearcher {

    func search(folder: URL, text: String) -> AsyncStream<[URL]> {
        AsyncStream { continuation in

            let query = NSMetadataQuery()

            query.searchScopes = [folder.path]

            query.predicate = NSPredicate(
                format: "%K CONTAINS[cd] %@",
                NSMetadataItemFSNameKey,
                text
            )

            var observers: [NSObjectProtocol] = []

            func extractResults() -> [URL] {
                query.results.compactMap { item in
                    guard let metadataItem = item as? NSMetadataItem,
                          let path = metadataItem.value(forAttribute: NSMetadataItemPathKey) as? String
                    else { return nil }

                    return URL(fileURLWithPath: path)
                }
            }

            observers.append(
                NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: query,
                    queue: nil
                ) { _ in
                    query.disableUpdates()
                    continuation.yield(extractResults())
                    query.enableUpdates()
                }
            )

            observers.append(
                NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidUpdate,
                    object: query,
                    queue: nil
                ) { _ in
                    continuation.yield(extractResults())
                }
            )

            query.start()

            continuation.onTermination = { _ in
                query.stop()

                for observer in observers {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
}
