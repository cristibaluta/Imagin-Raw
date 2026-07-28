//
//  ReviewGroupItem.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 28.07.2026.
//

import Foundation

struct ReviewGroupItem: Identifiable {
    let id = UUID()
    let group: DuplicateGroup
    let index: Int
    let totalGroups: Int
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onApprove: (PhotoItem) -> Void
    let onMarkForDeletion: (PhotoItem) -> Void
    let onNavigate: (Int) -> Void
}

struct ReviewGroupItemID: Identifiable {
    let id = UUID()
}
