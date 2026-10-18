//
//  ReviewViewOld.swift
//  Imagin Raw
//
//  Copy of the previous ReviewView implementation, kept for future reference.
//  Not used anywhere. Shows all photos side-by-side with name, rating, approve and delete actions.
//

import SwiftUI

struct ReviewViewOld: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var viewModel: ReviewViewModel

    @FocusState private var isFocused: Bool

    init(appState: AppState, viewModel: ReviewViewModel) {
        self.appState = appState
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: {
                    appState.reviewGroup = nil
                }) {
                    Label("Close", systemImage: "xmark")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: viewModel.navigateLeft) {
                        Image(systemName: "chevron.left")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(viewModel.groupIndex > 0 ? .primary : .secondary.opacity(0.3))
                    .disabled(viewModel.groupIndex <= 0)

                    Text("\(viewModel.groupIndex + 1)/\(viewModel.totalGroups)")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Button(action: viewModel.navigateRight) {
                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(viewModel.groupIndex < viewModel.totalGroups - 1 ? .primary : .secondary.opacity(0.3))
                    .disabled(viewModel.groupIndex >= viewModel.totalGroups - 1)
                }

                Spacer()

                Button(action: viewModel.toggleZoom) {
                    Label(viewModel.isZoomed ? "Fit" : "Zoom 100%",
                          systemImage: viewModel.isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(viewModel.isZoomed ? .accentColor : .secondary)
            }
            .padding(.horizontal, 16)
            .background(Color(IRColor.windowBackgroundColor))

            // Photo grid
            GeometryReader { geo in
                photoGrid(in: geo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(IRColor.windowBackgroundColor))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(characters: CharacterSet(charactersIn: "zZ")) { _ in
            viewModel.toggleZoom()
            return .handled
        }
        .onKeyPress(.escape) {
            Task {
                appState.reviewGroup = nil
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: " ")) { _ in
            Task {
                appState.reviewGroup = nil
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "12345")) { press in
            guard let photo = viewModel.hoveredPhoto,
                  let rating = Int(String(press.characters)) else {
                return .ignored
            }
            Task {
                viewModel.handleRating(rating, for: photo)
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "aA")) { _ in
            guard let photo = viewModel.hoveredPhoto else {
                return .ignored
            }
            viewModel.handleApprove(for: photo)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "xX")) { _ in
            guard let photo = viewModel.hoveredPhoto else {
                return .ignored
            }
            viewModel.handleToggleDelete(for: photo)
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
        .background(KeyEventInterceptor(onLeft: viewModel.navigateLeft,
                                        onRight: viewModel.navigateRight))
        #endif
    }

    // MARK: - Grid

    @ViewBuilder
    private func photoGrid(in geo: GeometryProxy) -> some View {
        let pad: CGFloat = 12
        let spacing: CGFloat = 12
        let available = CGSize(width: geo.size.width - pad * 2, height: geo.size.height - pad * 2)

        if let fitted = ReviewFitLayout.best(aspects: viewModel.photos.map { $0.fitAspectRatio },
                                             in: available,
                                             spacing: spacing) {
            // Everything fits on screen without scrolling
            VStack(spacing: spacing) {
                ForEach(Array(fitted.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.index) { item in
                            photoCard(for: viewModel.photos[item.index])
                                .frame(width: item.size.width, height: item.size.height)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(pad)
        } else {
            scrollingGrid(in: geo, pad: pad, spacing: spacing)
        }
    }

    /// Fallback used when there are too many photos to fit legibly: fixed-width columns + vertical scroll.
    @ViewBuilder
    private func scrollingGrid(in geo: GeometryProxy, pad: CGFloat, spacing: CGFloat) -> some View {
        let cols = viewModel.nrOfColumns
        let cardW = (geo.size.width - pad * 2 - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let columns = Array(repeating: GridItem(.fixed(cardW), spacing: spacing), count: cols)

        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(viewModel.photos) { photo in
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
                        previewsCacheManager: viewModel.previewsManager,
                        isZoomed: viewModel.isZoomed,
                        fullResImage: viewModel.fullResImages[photo.path],
                        isFullResLoading: viewModel.fullResLoading.contains(photo.path),
                        syncedMousePosition: $viewModel.syncedMousePosition,
                        hoveredPhotoId: $viewModel.hoveredPhotoId,
                        onRatingChanged: { rating in viewModel.handleRating(rating, for: photo) },
                        onApprove: { viewModel.handleApprove(for: photo) },
                        onMarkForDeletion: { viewModel.handleToggleDelete(for: photo) })
    }
}
