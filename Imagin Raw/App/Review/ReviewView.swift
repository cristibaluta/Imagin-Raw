//
//  ReviewView.swift
//  Imagin Raw
//
//  Full-screen review view for a single duplicate group.
//  Shows all photos side-by-side with name, rating, approve and delete actions.
//

import SwiftUI

struct ReviewView: View {
    let group: DuplicateGroup
    let groupIndex: Int
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onApprove: (PhotoItem) -> Void
    let onMarkForDeletion: (PhotoItem) -> Void
    let onDismiss: () -> Void

    // Live photo state — updated when actions are taken
    @State private var photos: [PhotoItem]

    // Zoom state
    @State private var isZoomed = false
    @State private var syncedMousePosition = CGPoint(x: 0.5, y: 0.5)
    @State private var fullResImages: [String: IRImage] = [:]
    @State private var fullResLoading: Set<String> = []

    // Focus
    @FocusState private var isFocused: Bool

    init(group: DuplicateGroup,
         groupIndex: Int,
         onRatingChanged: @escaping (PhotoItem, Int) -> Void,
         onApprove: @escaping (PhotoItem) -> Void,
         onMarkForDeletion: @escaping (PhotoItem) -> Void,
         onDismiss: @escaping () -> Void) {
        self.group = group
        self.groupIndex = groupIndex
        self.onRatingChanged = onRatingChanged
        self.onApprove = onApprove
        self.onMarkForDeletion = onMarkForDeletion
        self.onDismiss = onDismiss
        _photos = State(initialValue: group.photos)
    }

    private var similarity: Int {
        max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
    }

    private var isPortrait: Bool {
        guard let first = photos.first,
              let w = first.width,
              let h = first.height else {
            return true
        }
        return h > w
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: onDismiss) {
                    Label("Close", systemImage: "xmark")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Text("Group \(groupIndex + 1) — \(similarity)% similar")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: toggleZoom) {
                    Label(isZoomed ? "Fit" : "Zoom 100%",
                          systemImage: isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(isZoomed ? .accentColor : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            // Photo grid
            GeometryReader { geo in
                Group {
                    let hPad: CGFloat = 20
                    let spacing: CGFloat = 16
                    let cardW = (geo.size.width - hPad * 3 - spacing) / (isPortrait ? 3 : 2)
                    let columns = isPortrait
                    ? [
                        GridItem(.fixed(cardW), spacing: spacing),
                        GridItem(.fixed(cardW), spacing: spacing),
                        GridItem(.fixed(cardW), spacing: spacing)
                    ]
                    : [
                        GridItem(.fixed(cardW), spacing: spacing),
                        GridItem(.fixed(cardW), spacing: spacing)
                    ]
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(photos) { photo in
                                ReviewPhotoCard(
                                    photo: photo,
                                    isZoomed: isZoomed,
                                    fullResImage: fullResImages[photo.path],
                                    isFullResLoading: fullResLoading.contains(photo.path),
                                    syncedMousePosition: $syncedMousePosition,
                                    onRatingChanged: { rating in
                                        onRatingChanged(photo, rating)
                                        updateLocalPhoto(photo) { p in
                                            let oldXmp = p.xmp
                                            let newXmp = XmpMetadata(
                                                label: oldXmp?.label, rating: rating,
                                                creator: oldXmp?.creator, rights: oldXmp?.rights,
                                                createDate: oldXmp?.createDate, modifyDate: oldXmp?.modifyDate,
                                                cameraModel: oldXmp?.cameraModel, lens: oldXmp?.lens,
                                                focalLength: oldXmp?.focalLength, aperture: oldXmp?.aperture,
                                                shutterSpeed: oldXmp?.shutterSpeed, iso: oldXmp?.iso,
                                                exposureBias: oldXmp?.exposureBias
                                            )
                                            return PhotoItem(
                                                id: p.id, path: p.path, xmp: newXmp,
                                                dateCreated: p.dateCreated, toDelete: p.toDelete,
                                                hasACR: p.hasACR, hasJPG: p.hasJPG,
                                                inCameraRating: p.inCameraRating, isRawFile: p.isRawFile,
                                                fileSizeBytes: p.fileSizeBytes, width: p.width, height: p.height,
                                                cameraMake: p.cameraMake, cameraModel: p.cameraModel
                                            )
                                        }
                                    },
                                    onApprove: {
                                        onApprove(photo)
                                        updateLocalPhoto(photo) { p in
                                            let oldXmp = p.xmp
                                            let isApproved = oldXmp?.label == "Approved"
                                            let newXmp = XmpMetadata(
                                                label: isApproved ? nil : "Approved", rating: oldXmp?.rating,
                                                creator: oldXmp?.creator, rights: oldXmp?.rights,
                                                createDate: oldXmp?.createDate, modifyDate: oldXmp?.modifyDate,
                                                cameraModel: oldXmp?.cameraModel, lens: oldXmp?.lens,
                                                focalLength: oldXmp?.focalLength, aperture: oldXmp?.aperture,
                                                shutterSpeed: oldXmp?.shutterSpeed, iso: oldXmp?.iso,
                                                exposureBias: oldXmp?.exposureBias
                                            )
                                            return PhotoItem(
                                                id: p.id, path: p.path, xmp: newXmp,
                                                dateCreated: p.dateCreated, toDelete: p.toDelete,
                                                hasACR: p.hasACR, hasJPG: p.hasJPG,
                                                inCameraRating: p.inCameraRating, isRawFile: p.isRawFile,
                                                fileSizeBytes: p.fileSizeBytes, width: p.width, height: p.height,
                                                cameraMake: p.cameraMake, cameraModel: p.cameraModel
                                            )
                                        }
                                    },
                                    onMarkForDeletion: {
                                        onMarkForDeletion(photo)
                                        updateLocalPhoto(photo) { p in
                                            return PhotoItem(
                                                id: p.id, path: p.path, xmp: p.xmp,
                                                dateCreated: p.dateCreated, toDelete: !p.toDelete,
                                                hasACR: p.hasACR, hasJPG: p.hasJPG,
                                                inCameraRating: p.inCameraRating, isRawFile: p.isRawFile,
                                                fileSizeBytes: p.fileSizeBytes, width: p.width, height: p.height,
                                                cameraMake: p.cameraMake, cameraModel: p.cameraModel
                                            )
                                        }
                                    }
                                )
                            }
                        }
                        .padding(hPad)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(characters: CharacterSet(charactersIn: "zZ")) { _ in
            toggleZoom()
            return .handled
        }
        .onAppear {
            // Delay focus grab so the view is fully in the window hierarchy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onTapGesture { isFocused = true }
    }

    // MARK: - Zoom

    private func toggleZoom() {
        isZoomed.toggle()
        if isZoomed {
            loadAllFullRes()
        }
    }

    private func loadAllFullRes() {
        for photo in photos {
            guard fullResImages[photo.path] == nil else { continue }
            fullResLoading.insert(photo.path)
            FullResManager.shared.loadFullRes(for: photo.path) { image in
                fullResLoading.remove(photo.path)
                if let image {
                    fullResImages[photo.path] = image
                }
            }
        }
    }

    private func updateLocalPhoto(_ photo: PhotoItem, transform: (PhotoItem) -> PhotoItem) {
        if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
            photos[idx] = transform(photos[idx])
        }
    }
}
