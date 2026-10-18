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
    /// Page of the displayed photos when reviewing a page of the selection, nil otherwise
    @Published var pageInfo: PageInfo?

    let previewsManager: PhotoCacheManager
    private let fullResManager: PhotoCacheManager

    var group: DuplicateGroup = DuplicateGroup(photos: [], distance: 0)
    var groupIndex: Int = 0
    var totalGroups: Int = 0

    var onRatingChanged: ((PhotoItem, Int) -> Void)? = nil
    var onApprove: ((PhotoItem) -> Void)? = nil
    var onMarkForDeletion: ((PhotoItem) -> Void)? = nil
    var onRemove: ((PhotoItem) -> Void)? = nil
    var onNavigate: ((Int) -> Void)? = nil
    var onPageChange: ((Int) -> Void)? = nil
    var isPageReview = false

    init(previewsCacheManager: PhotoCacheManager, fullResCacheManager: PhotoCacheManager) {
        self.previewsManager = previewsCacheManager
        self.fullResManager = fullResCacheManager
    }

    func setup(with reviewGroupItem: ReviewGroupItem) {
        self.group = reviewGroupItem.group
        self.photos = reviewGroupItem.group.photos
        self.groupIndex = reviewGroupItem.index
        self.totalGroups = reviewGroupItem.totalGroups
        self.onRatingChanged = reviewGroupItem.onRatingChanged
        self.onApprove = reviewGroupItem.onApprove
        self.onMarkForDeletion = reviewGroupItem.onMarkForDeletion
        self.onNavigate = reviewGroupItem.onNavigate
        self.isPageReview = reviewGroupItem.isPageReview
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
              let w = first.exif?.width,
              let h = first.exif?.height else {
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
        let oldXmp = photo.xmp
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
        let newPhoto = PhotoItem(id: photo.id,
                                 url: photo.url,
                                 path: photo.path,
                                 dateCreated: photo.dateCreated,
                                 dateModified: photo.dateModified,
                                 hasACR: photo.hasACR,
                                 companionImageExt: photo.companionImageExt,
                                 hasGainMap: photo.hasGainMap,
                                 hasXMP: photo.hasXMP,
                                 xmp: newXmp,
                                 exif: photo.exif,
                                 fileSizeBytes: photo.fileSizeBytes,
                                 state: photo.state)
        updateLocalPhoto(newPhoto)
    }

    func handleApprove(for photo: PhotoItem) {
        onApprove?(photo)
        let oldXmp = photo.xmp
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
        let newPhoto = PhotoItem(id: photo.id,
                                 url: photo.url,
                                 path: photo.path,
                                 dateCreated: photo.dateCreated,
                                 dateModified: photo.dateModified,
                                 hasACR: photo.hasACR,
                                 companionImageExt: photo.companionImageExt,
                                 hasGainMap: photo.hasGainMap,
                                 hasXMP: photo.hasXMP,
                                 xmp: newXmp,
                                 exif: photo.exif,
                                 fileSizeBytes: photo.fileSizeBytes,
                                 state: photo.state)
        updateLocalPhoto(newPhoto)
    }

    /// Hovered photo, or all photos when the mouse is outside any of them.
    private var targetPhotos: [PhotoItem] {
        if let photo = hoveredPhoto {
            return [photo]
        }
        return photos
    }

    func rateTargets(_ rating: Int) {
        for photo in targetPhotos {
            handleRating(rating, for: photo)
        }
    }

    func approveTargets() {
        let targets = targetPhotos
        let allApproved = targets.allSatisfy { $0.xmp?.label == "Approved" }
        for photo in targets where allApproved || photo.xmp?.label != "Approved" {
            handleApprove(for: photo)
        }
    }

    func toggleDeleteTargets() {
        let targets = targetPhotos
        let allRejected = targets.allSatisfy { $0.state == .rejected }
        for photo in targets where allRejected || photo.state != .rejected {
            handleToggleDelete(for: photo)
        }
    }

    /// Removes the photo from the review (and from the selection when reviewing a page), keeping at least one photo.
    func handleRemove(for photo: PhotoItem) {
        guard photos.count > 1 else {
            return
        }
        if isPageReview {
            onRemove?(photo)
        }
        photos.removeAll { $0.id == photo.id }
        if hoveredPhotoId == photo.id {
            hoveredPhotoId = nil
        }
    }

    func handleToggleDelete(for photo: PhotoItem) {
        onMarkForDeletion?(photo)
        let newState: PhotoState = photo.state == .rejected ? .none : .rejected
        let newPhoto = PhotoItem(id: photo.id,
                                 url: photo.url,
                                 path: photo.path,
                                 dateCreated: photo.dateCreated,
                                 dateModified: photo.dateModified,
                                 hasACR: photo.hasACR,
                                 companionImageExt: photo.companionImageExt,
                                 hasGainMap: photo.hasGainMap,
                                 hasXMP: photo.hasXMP,
                                 xmp: photo.xmp,
                                 exif: photo.exif,
                                 fileSizeBytes: photo.fileSizeBytes,
                                 state: newState)
        updateLocalPhoto(newPhoto)
    }

    var showsPagination: Bool {
        isPageReview ? (pageInfo?.count ?? 0) > 1 : totalGroups > 1
    }

    var paginationText: String {
        if isPageReview, let info = pageInfo {
            return "Page \(info.index + 1) of \(info.count)"
        }
        return "\(groupIndex + 1) of \(totalGroups)"
    }

    var canNavigateLeft: Bool {
        isPageReview ? (pageInfo?.index ?? 0) > 0 : groupIndex > 0
    }

    var canNavigateRight: Bool {
        if isPageReview {
            guard let info = pageInfo else {
                return false
            }
            return info.index < info.count - 1
        }
        return groupIndex < totalGroups - 1
    }

    func navigateLeft() {
        guard canNavigateLeft else {
            return
        }
        if isPageReview {
            onPageChange?(-1)
        } else {
            onNavigate?(groupIndex - 1)
        }
    }

    func navigateRight() {
        guard canNavigateRight else {
            return
        }
        if isPageReview {
            onPageChange?(1)
        } else {
            onNavigate?(groupIndex + 1)
        }
    }

    // MARK: - Private

    private func updateLocalPhoto(_ photo: PhotoItem) {
        if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
            Task {
                photos[idx] = photo
            }
        }
    }
}
