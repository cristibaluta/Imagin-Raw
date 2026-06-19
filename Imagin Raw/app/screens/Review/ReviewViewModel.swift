//
//  ReviewViewModel.swift
//  Imagin Raw
//

import SwiftUI

@MainActor
class ReviewViewModel: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var isZoomed = false
    @Published var syncedMousePosition = CGPoint(x: 0.5, y: 0.5)
    @Published var fullResImages: [String: IRImage] = [:]
    @Published var fullResLoading: Set<String> = []
    @Published var hoveredPhotoId: UUID? = nil

    let previewsManager: PhotoCacheManager
    private let fullResManager: PhotoCacheManager

    var group: DuplicateGroup = DuplicateGroup(photos: [], distance: 0)
    var groupIndex: Int = 0
    var totalGroups: Int = 0

    var onRatingChanged: ((PhotoItem, Int) -> Void)? = nil
    var onApprove: ((PhotoItem) -> Void)? = nil
    var onMarkForDeletion: ((PhotoItem) -> Void)? = nil
    var onNavigate: ((Int) -> Void)? = nil

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsManager = previewsCacheManager
        self.fullResManager = fullResCacheManager
    }

    func setup(with reviewGroupItem: ReviewGroupItem) {
        self.group = reviewGroupItem.group
        self.groupIndex = 0
        self.totalGroups = reviewGroupItem.totalGroups
        self.onRatingChanged = reviewGroupItem.onRatingChanged
        self.onApprove = reviewGroupItem.onApprove
        self.onMarkForDeletion = reviewGroupItem.onMarkForDeletion
        self.onNavigate = reviewGroupItem.onNavigate
        self.photos = reviewGroupItem.group.photos
    }

    var hoveredPhoto: PhotoItem? {
        guard let id = hoveredPhotoId else {
            return nil
        }
        return photos.first { $0.id == id }
    }

    var similarity: Int {
        max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
    }

    var isPortrait: Bool {
        guard let first = photos.first,
              let w = first.width,
              let h = first.height else {
            return true
        }
        return h > w
    }

    var nrOfColumns: Int {
        (isPortrait && photos.count >= 3) ? 3 : 2
    }

    // MARK: - Zoom

    func toggleZoom() {
        isZoomed.toggle()
        if isZoomed {
            loadAllFullRes()
        }
    }

    private func loadAllFullRes() {
        for photo in photos {
            guard fullResImages[photo.path] == nil else {
                continue
            }
            fullResLoading.insert(photo.path)
            Task {
                let image = await fullResManager.getImage(for: photo)
                self.fullResLoading.remove(photo.path)
                if let image {
                    self.fullResImages[photo.path] = image
                }
            }
        }
    }

    // MARK: - Actions

    func handleRating(_ rating: Int, for photo: PhotoItem) {
        onRatingChanged?(photo, rating)
        updateLocalPhoto(photo) { p in
            let oldXmp = p.xmp
            let newXmp = XmpMetadata(label: oldXmp?.label,
                                     rating: rating,
                                     creator: oldXmp?.creator,
                                     rights: oldXmp?.rights,
                                     createDate: oldXmp?.createDate,
                                     modifyDate: oldXmp?.modifyDate,
                                     cameraModel: oldXmp?.cameraModel,
                                     lens: oldXmp?.lens,
                                     focalLength: oldXmp?.focalLength,
                                     aperture: oldXmp?.aperture,
                                     shutterSpeed: oldXmp?.shutterSpeed,
                                     iso: oldXmp?.iso,
                                     exposureBias: oldXmp?.exposureBias,
                                     hasEdits: oldXmp?.hasEdits ?? false)
            return PhotoItem(id: p.id,
                             url: p.url,
                             path: p.path,
                             dateCreated: p.dateCreated,
                             toDelete: p.toDelete,
                             hasACR: p.hasACR,
                             hasJPG: p.hasJPG,
                             hasXMP: p.hasXMP,
                             xmp: newXmp,
                             inCameraRating: p.inCameraRating,
                             isRawFile: p.isRawFile,
                             fileSizeBytes: p.fileSizeBytes,
                             width: p.width,
                             height: p.height,
                             cameraMake: p.cameraMake,
                             cameraModel: p.cameraModel)
        }
    }

    func handleApprove(for photo: PhotoItem) {
        onApprove?(photo)
        updateLocalPhoto(photo) { p in
            let oldXmp = p.xmp
            let isApproved = oldXmp?.label == "Approved"
            let newXmp = XmpMetadata(label: isApproved ? nil : "Approved",
                                     rating: oldXmp?.rating,
                                     creator: oldXmp?.creator,
                                     rights: oldXmp?.rights,
                                     createDate: oldXmp?.createDate,
                                     modifyDate: oldXmp?.modifyDate,
                                     cameraModel: oldXmp?.cameraModel,
                                     lens: oldXmp?.lens,
                                     focalLength: oldXmp?.focalLength,
                                     aperture: oldXmp?.aperture,
                                     shutterSpeed: oldXmp?.shutterSpeed,
                                     iso: oldXmp?.iso,
                                     exposureBias: oldXmp?.exposureBias,
                                     hasEdits: oldXmp?.hasEdits ?? false)
            return PhotoItem(id: p.id,
                             url: p.url,
                             path: p.path,
                             dateCreated: p.dateCreated,
                             toDelete: p.toDelete,
                             hasACR: p.hasACR,
                             hasJPG: p.hasJPG,
                             hasXMP: p.hasXMP,
                             xmp: newXmp,
                             inCameraRating: p.inCameraRating,
                             isRawFile: p.isRawFile,
                             fileSizeBytes: p.fileSizeBytes,
                             width: p.width,
                             height: p.height,
                             cameraMake: p.cameraMake,
                             cameraModel: p.cameraModel)
        }
    }

    func handleToggleDelete(for photo: PhotoItem) {
        onMarkForDeletion?(photo)
        updateLocalPhoto(photo) { p in
            return PhotoItem(id: p.id,
                             url: p.url,
                             path: p.path,
                             dateCreated: p.dateCreated,
                             toDelete: !p.toDelete,
                             hasACR: p.hasACR,
                             hasJPG: p.hasJPG,
                             hasXMP: p.hasXMP,
                             xmp: p.xmp,
                             inCameraRating: p.inCameraRating,
                             isRawFile: p.isRawFile,
                             fileSizeBytes: p.fileSizeBytes,
                             width: p.width,
                             height: p.height,
                             cameraMake: p.cameraMake,
                             cameraModel: p.cameraModel)
        }
    }

    func navigateLeft() {
        guard groupIndex > 0 else {
            return
        }
        onNavigate?(groupIndex - 1)
    }

    func navigateRight() {
        guard groupIndex < totalGroups - 1 else {
            return
        }
        onNavigate?(groupIndex + 1)
    }

    // MARK: - Private

    private func updateLocalPhoto(_ photo: PhotoItem, transform: (PhotoItem) -> PhotoItem) {
        if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
            photos[idx] = transform(photos[idx])
        }
    }
}
