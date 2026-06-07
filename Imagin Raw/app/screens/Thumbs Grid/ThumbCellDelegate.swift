//
//  ThumbCellCallbacks.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05/06/2026.
//

import Foundation

protocol ThumbCellDelegate: Sendable {
    func onTap(photo: PhotoItem, modifiers: NSEvent.ModifierFlags) -> Void
    func onDoubleClick(photo: PhotoItem) -> Void
    func onRatingChanged(photo: PhotoItem, rating: Int) -> Void
    func onLabelChanged(photo: PhotoItem, label: String?) -> Void
    func onMoveToTrash(photo: PhotoItem) -> Void
    func onCopyTo(photo: PhotoItem) -> Void
    func onRenameTo(photo: PhotoItem) -> Void
    func onMoveAllMarkedToTrash(photo: PhotoItem) -> Void
    func onApprove(photo: PhotoItem) -> Void
    func onReject(photo: PhotoItem) -> Void
    func onReviewSelected(photo: PhotoItem) -> Void
    func onOpenWith(photo: PhotoItem, app: PhotoApp) -> Void
    func selectedPhotosCount() -> Int
    func markedForDeletionCount() -> Int
    func discoveredPhotoApps() -> [PhotoApp]
}
