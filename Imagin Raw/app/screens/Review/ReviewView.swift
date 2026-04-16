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
    let totalGroups: Int
    let onNavigate: (Int) -> Void

    // Live photo state — updated when actions are taken
    @State private var photos: [PhotoItem]

    // Zoom state
    @State private var isZoomed = false
    @State private var syncedMousePosition = CGPoint(x: 0.5, y: 0.5)
    @State private var fullResImages: [String: IRImage] = [:]
    @State private var fullResLoading: Set<String> = []

    // Focus
    @FocusState private var isFocused: Bool

    // Hover tracking for keyboard shortcuts
    @State private var hoveredPhotoId: UUID? = nil

    init(group: DuplicateGroup,
         groupIndex: Int,
         onRatingChanged: @escaping (PhotoItem, Int) -> Void,
         onApprove: @escaping (PhotoItem) -> Void,
         onMarkForDeletion: @escaping (PhotoItem) -> Void,
         onDismiss: @escaping () -> Void,
         totalGroups: Int,
         onNavigate: @escaping (Int) -> Void) {
        self.group = group
        self.groupIndex = groupIndex
        self.onRatingChanged = onRatingChanged
        self.onApprove = onApprove
        self.onMarkForDeletion = onMarkForDeletion
        self.onDismiss = onDismiss
        self.totalGroups = totalGroups
        self.onNavigate = onNavigate
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

    private var nrOfColumns: Int {
        (isPortrait && photos.count >= 3) ? 3 : 2
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

                HStack(spacing: 8) {
                    Button(action: { onNavigate(groupIndex - 1) }) {
                        Image(systemName: "chevron.left")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(groupIndex > 0 ? .primary : .secondary.opacity(0.3))
                    .disabled(groupIndex <= 0)

                    Text("Group \(groupIndex + 1)/\(totalGroups) — \(similarity)% similar")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Button(action: { onNavigate(groupIndex + 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(groupIndex < totalGroups - 1 ? .primary : .secondary.opacity(0.3))
                    .disabled(groupIndex >= totalGroups - 1)
                }

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
            .background(Color(IRColor.windowBackgroundColor))

            // Photo grid
            GeometryReader { geo in
                photoGrid(in: geo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(IRColor.underPageBackgroundColor))
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
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "12345")) { press in
            guard let photo = hoveredPhoto,
                  let rating = Int(String(press.characters)) else {
                return .ignored
            }
            onRatingChanged(photo, rating)
            applyRating(rating, to: photo)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "aA")) { _ in
            guard let photo = hoveredPhoto else {
                return .ignored
            }
            onApprove(photo)
            applyApprove(to: photo)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "xX")) { _ in
            guard let photo = hoveredPhoto else {
                return .ignored
            }
            onMarkForDeletion(photo)
            applyToggleDelete(to: photo)
            return .handled
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onTapGesture {
            isFocused = true
        }
        #if os(macOS)
        .background(KeyEventInterceptor(onLeft: {
            guard groupIndex > 0 else { return }
            onNavigate(groupIndex - 1)
        }, onRight: {
            guard groupIndex < totalGroups - 1 else { return }
            onNavigate(groupIndex + 1)
        }))
        #endif
    }

    // MARK: - Grid

    @ViewBuilder
    private func photoGrid(in geo: GeometryProxy) -> some View {
        let pad: CGFloat = 12
        let spacing: CGFloat = 12
        let cols = nrOfColumns
        let cardW = (geo.size.width - pad * 2 - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let rows = Int(ceil(Double(photos.count) / Double(cols)))
//        let cardH = (geo.size.height - pad * 2 - spacing * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))
        let columns = Array(repeating: GridItem(.fixed(cardW), spacing: spacing), count: cols)

        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(photos) { photo in
                    photoCard(for: photo)
                        .frame(width: cardW)
                }
            }
        }
        .padding(pad)
    }

    @ViewBuilder
    private func photoCard(for photo: PhotoItem) -> some View {
        ReviewPhotoCard(photo: photo,
                        isZoomed: isZoomed,
                        fullResImage: fullResImages[photo.path],
                        isFullResLoading: fullResLoading.contains(photo.path),
                        syncedMousePosition: $syncedMousePosition,
                        hoveredPhotoId: $hoveredPhotoId,
                        onRatingChanged: { rating in
                            onRatingChanged(photo, rating)
                            applyRating(rating, to: photo)
                        },
                        onApprove: {
                            onApprove(photo)
                            applyApprove(to: photo)
                        },
                        onMarkForDeletion: {
                            onMarkForDeletion(photo)
                            applyToggleDelete(to: photo)
                        })
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
            guard fullResImages[photo.path] == nil else {
                continue
            }
            fullResLoading.insert(photo.path)

            FullResManager.shared.loadFullRes(for: photo) { image in
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

    private func applyRating(_ rating: Int, to photo: PhotoItem) {
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
                                     exposureBias: oldXmp?.exposureBias)
            return PhotoItem(id: p.id,
                             path: p.path,
                             xmp: newXmp,
                             dateCreated: p.dateCreated,
                             toDelete: p.toDelete,
                             hasACR: p.hasACR,
                             hasJPG: p.hasJPG,
                             inCameraRating: p.inCameraRating,
                             isRawFile: p.isRawFile,
                             fileSizeBytes: p.fileSizeBytes,
                             width: p.width,
                             height: p.height,
                             cameraMake: p.cameraMake,
                             cameraModel: p.cameraModel)
        }
    }

    private func applyApprove(to photo: PhotoItem) {
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
    }

    private func applyToggleDelete(to photo: PhotoItem) {
        updateLocalPhoto(photo) { p in
            return PhotoItem(id: p.id,
                             path: p.path,
                             xmp: p.xmp,
                             dateCreated: p.dateCreated,
                             toDelete: !p.toDelete,
                             hasACR: p.hasACR,
                             hasJPG: p.hasJPG,
                             inCameraRating: p.inCameraRating,
                             isRawFile: p.isRawFile,
                             fileSizeBytes: p.fileSizeBytes,
                             width: p.width,
                             height: p.height,
                             cameraMake: p.cameraMake,
                             cameraModel: p.cameraModel)
        }
    }

    private var hoveredPhoto: PhotoItem? {
        guard let id = hoveredPhotoId else {
            return nil
        }
        return photos.first { $0.id == id }
    }
}
