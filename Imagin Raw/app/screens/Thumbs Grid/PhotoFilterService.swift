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

    static func apply(labels: Set<PhotoLabel>, ratings: Set<Int>, names: Set<String>, to photos: [PhotoItem]) -> [PhotoItem] {
        return photos.filter { photo in
            // Name has priority
            let photoName = photo.url.deletingPathExtension().lastPathComponent
            if names.contains(photoName) {
                return true
            }
            let label = PhotoLabel(rawValue: photo.xmp?.label ?? "") ?? .noLabel
            let rating = photo.xmp?.rating.flatMap { $0 > 0 ? $0 : nil } ?? photo.inCameraRating ?? 0

            return labels.contains(label) ||
                    ratings.contains(rating) ||
                    (labels.contains(.rejected) && photo.toDelete) ||
                    (labels.contains(.noLabel) && label == .noLabel && !photo.toDelete)
        }
    }

    // MARK: - Sort

    static func comparator(for option: ThumbGridViewModel.SortOption) -> (PhotoItem, PhotoItem) -> Bool {
        switch option {
            case .name:
                return { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            case .dateCaptured:
                return {
                    if let d0 = $0.dateCaptured, let d1 = $1.dateCaptured {
                        return d0 < d1
                    } else {
                        return $0.path < $1.path
                    }
                }
            case .dateModified:
                return {
                    if let d0 = $0.dateModified ?? $0.dateCaptured, let d1 = $1.dateModified ?? $1.dateCaptured {
                        return d0 < d1
                    } else {
                        return $0.path < $1.path
                    }
                }
            case .fileType:
                return {
                    let e1 = $0.url.pathExtension.lowercased()
                    let e2 = $1.url.pathExtension.lowercased()
                    return e1 != e2 ? e1 < e2 : $0.path < $1.path
                }
            case .rating:
                return {
                    let r1 = $0.effectiveRating, r2 = $1.effectiveRating
                    return r1 != r2 ? r1 > r2 : $0.path < $1.path
                }
        }
    }

    // MARK: - Date groups

    static func buildDateGroups(from photos: [PhotoItem],
                                sortOption: ThumbGridViewModel.SortOption) -> [(title: String, photos: [PhotoItem])] {
        switch sortOption {
            case .name:         return []
            case .dateCaptured: return groupByKey(photos) { ($0.dateCaptured ?? Date()).EEEEMMMdyyyy }
            case .dateModified: return groupByKey(photos) { ($0.dateModified ?? $0.dateCaptured ?? Date()).EEEEMMMdyyyy }
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

    static func availableLabels(from photos: [PhotoItem]) -> [PhotoLabel] {
        var labelSet = Set<PhotoLabel>()
        var hasToDelete = false
        for photo in photos {
            if photo.toDelete {
                hasToDelete = true
            }
            if let label = PhotoLabel(rawValue: photo.xmp?.label ?? "") {
                labelSet.insert(label)
            }
        }
        var result: [PhotoLabel] = []
        if !labelSet.isEmpty {
            result.append(.noLabel)
        }
        let labels: [PhotoLabel] = [.select, .second, .approved, .review, .todo]
        for label in labels where labelSet.contains(label) {
            result.append(label)
        }
        if hasToDelete {
            result.append(.rejected)
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
