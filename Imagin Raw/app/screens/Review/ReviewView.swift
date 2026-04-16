//
//  ReviewView.swift
//  Imagin Raw
//
//  Full-screen review view for a single duplicate group.
//  Shows all photos side-by-side with name, rating, approve and delete actions.
//

import SwiftUI

struct ReviewView: View {
    @StateObject private var model: ReviewViewModel

    @FocusState private var isFocused: Bool

    init(group: DuplicateGroup,
         groupIndex: Int,
         onRatingChanged: @escaping (PhotoItem, Int) -> Void,
         onApprove: @escaping (PhotoItem) -> Void,
         onMarkForDeletion: @escaping (PhotoItem) -> Void,
         onDismiss: @escaping () -> Void,
         totalGroups: Int,
         onNavigate: @escaping (Int) -> Void) {
        _model = StateObject(wrappedValue: ReviewViewModel(group: group,
                                                           groupIndex: groupIndex,
                                                           totalGroups: totalGroups,
                                                           onRatingChanged: onRatingChanged,
                                                           onApprove: onApprove,
                                                           onMarkForDeletion: onMarkForDeletion,
                                                           onDismiss: onDismiss,
                                                           onNavigate: onNavigate))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: model.onDismiss) {
                    Label("Close", systemImage: "xmark")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: model.navigateLeft) {
                        Image(systemName: "chevron.left")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(model.groupIndex > 0 ? .primary : .secondary.opacity(0.3))
                    .disabled(model.groupIndex <= 0)

                    Text("Group \(model.groupIndex + 1)/\(model.totalGroups) — \(model.similarity)% similar")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Button(action: model.navigateRight) {
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(model.groupIndex < model.totalGroups - 1 ? .primary : .secondary.opacity(0.3))
                    .disabled(model.groupIndex >= model.totalGroups - 1)
                }

                Spacer()

                Button(action: model.toggleZoom) {
                    Label(model.isZoomed ? "Fit" : "Zoom 100%",
                          systemImage: model.isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(model.isZoomed ? .accentColor : .secondary)
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
            model.toggleZoom()
            return .handled
        }
        .onKeyPress(.escape) {
            model.onDismiss()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: " ")) { _ in
            model.onDismiss()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "12345")) { press in
            guard let photo = model.hoveredPhoto,
                  let rating = Int(String(press.characters)) else {
                return .ignored
            }
            model.handleRating(rating, for: photo)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "aA")) { _ in
            guard let photo = model.hoveredPhoto else {
                return .ignored
            }
            model.handleApprove(for: photo)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "xX")) { _ in
            guard let photo = model.hoveredPhoto else {
                return .ignored
            }
            model.handleToggleDelete(for: photo)
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
        .background(KeyEventInterceptor(onLeft: model.navigateLeft,
                                        onRight: model.navigateRight))
        #endif
    }

    // MARK: - Grid

    @ViewBuilder
    private func photoGrid(in geo: GeometryProxy) -> some View {
        let pad: CGFloat = 12
        let spacing: CGFloat = 12
        let cols = model.nrOfColumns
        let cardW = (geo.size.width - pad * 2 - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let columns = Array(repeating: GridItem(.fixed(cardW), spacing: spacing), count: cols)

        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(model.photos) { photo in
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
                        isZoomed: model.isZoomed,
                        fullResImage: model.fullResImages[photo.path],
                        isFullResLoading: model.fullResLoading.contains(photo.path),
                        syncedMousePosition: $model.syncedMousePosition,
                        hoveredPhotoId: $model.hoveredPhotoId,
                        onRatingChanged: { rating in model.handleRating(rating, for: photo) },
                        onApprove: { model.handleApprove(for: photo) },
                        onMarkForDeletion: { model.handleToggleDelete(for: photo) })
    }
}
