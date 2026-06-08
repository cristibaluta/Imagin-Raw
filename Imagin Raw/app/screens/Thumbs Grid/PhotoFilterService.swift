//
//  PhotoFilterService.swift
//  Imagin Raw
//
//  Filtering, sorting, and date-group building for photo arrays.
//

import Foundation
import SwiftUI

struct PhotoFilterService {

    // MARK: - Filter

    static func apply(labels: Set<String>, ratings: Set<Int>, to photos: [PhotoItem]) -> [PhotoItem] {
        return photos.filter { photo in
            let label = photo.xmp?.label ?? ""
            let rating = photo.xmp?.rating.flatMap { $0 > 0 ? $0 : nil } ?? photo.inCameraRating ?? 0
            return labels.contains(label) ||
                    ratings.contains(rating) ||
                    (labels.contains("Rejected") && photo.toDelete) ||
                    (labels.contains("No Label") && label.isEmpty && !photo.toDelete)
        }
    }

    // MARK: - Sort

    static func comparator(for option: ThumbGridViewModel.SortOption) -> (PhotoItem, PhotoItem) -> Bool {
        switch option {
        case .name:
                return { URL(fileURLWithPath: $0.path)
                        .lastPathComponent
                        .localizedStandardCompare(URL(fileURLWithPath: $1.path).lastPathComponent) == .orderedAscending
                }
        case .dateCaptured:
            return { $0.dateCreated < $1.dateCreated }
        case .dateModified:
            return { ($0.dateModified ?? $0.dateCreated) < ($1.dateModified ?? $1.dateCreated) }
        case .fileType:
            return { a, b in
                let e1 = URL(fileURLWithPath: a.path).pathExtension.lowercased()
                let e2 = URL(fileURLWithPath: b.path).pathExtension.lowercased()
                return e1 != e2 ? e1 < e2 : a.dateCreated < b.dateCreated
            }
        case .rating:
            return { a, b in
                let r1 = a.effectiveRating, r2 = b.effectiveRating
                return r1 != r2 ? r1 > r2 : a.dateCreated < b.dateCreated
            }
        }
    }

    // MARK: - Date groups

    static func buildDateGroups(from photos: [PhotoItem],
                                sortOption: ThumbGridViewModel.SortOption) -> [(title: String, photos: [PhotoItem])] {
        switch sortOption {
            case .name:         return []
            case .dateCaptured: return groupByKey(photos) { $0.dateCreated.EEEEMMMdyyyy }
            case .dateModified: return groupByKey(photos) { ($0.dateModified ?? $0.dateCreated).EEEEMMMdyyyy }
            case .fileType:     return groupByKey(photos) { URL(fileURLWithPath: $0.path).pathExtension.uppercased() }
            case .rating:
                return groupByKey(photos) { photo in
                    let r = photo.effectiveRating
                    return r == 0 ? "No Rating" : "\(r) Star\(r == 1 ? "" : "s")"
                }
        }
    }

    private static func groupByKey(_ photos: [PhotoItem],
                                   key: (PhotoItem) -> String) -> [(title: String, photos: [PhotoItem])] {
        var groups: [(title: String, photos: [PhotoItem])] = []
        var currentKey: String? = nil
        var currentPhotos: [PhotoItem] = []
        for photo in photos {
            let k = key(photo)
            if k != currentKey {
                if let existing = currentKey, !currentPhotos.isEmpty {
                    groups.append((title: existing, photos: currentPhotos))
                }
                currentKey = k
                currentPhotos = [photo]
            } else {
                currentPhotos.append(photo)
            }
        }
        if let last = currentKey, !currentPhotos.isEmpty {
            groups.append((title: last, photos: currentPhotos))
        }
        return groups
    }

    // MARK: - Available labels

    static func availableLabels(from photos: [PhotoItem]) -> [String] {
        var labelSet = Set<String>()
        var hasToDelete = false
        for photo in photos {
            if photo.toDelete {
                hasToDelete = true
            }
            if let label = photo.xmp?.label, !label.isEmpty {
                labelSet.insert(label)
            }
        }
        var result: [String] = []
        if !labelSet.isEmpty {
            result.append("No Label")
        }
        for label in ["Select", "Second", "Approved", "Review", "To Do"] where labelSet.contains(label) {
            result.append(label)
        }
        if hasToDelete {
            result.append("Rejected")
        }
        return result
    }

    static func availableRatings(from photos: [PhotoItem]) -> [Int] {
        var ratingSet = Set<Int>()
        for photo in photos {
            let rating = photo.effectiveRating
            if rating > 0 {
                ratingSet.insert(rating)
            }
        }
        return Array(ratingSet)
    }
}
