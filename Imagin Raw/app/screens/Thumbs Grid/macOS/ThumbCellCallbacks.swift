//
//  ThumbCellCallbacks.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05/06/2026.
//

import SwiftUI

struct ThumbCellCallbacks {
    let onTap: (PhotoItem, NSEvent.ModifierFlags) -> Void
    let onDoubleClick: (PhotoItem) -> Void
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onLabelChanged: (PhotoItem, String?) -> Void
    let onMoveToTrash: (PhotoItem) -> Void
    let onCopyTo: (PhotoItem) -> Void
    let onRenameTo: (PhotoItem) -> Void
    let onMoveAllMarkedToTrash: (PhotoItem) -> (count: Int, action: () -> Void)?
    let onApprove: (PhotoItem) -> Void
    let onReject: (PhotoItem) -> Void
    let onReviewSelected: (PhotoItem) -> Void
    let onOpenWith: (PhotoItem, PhotoApp) -> Void
    var externalAppManager: ExternalAppManager? = nil
    var selectedPhotosCount: () -> Int = { 0 }
}
