//
//  ReviewView.swift
//  Imagin Raw
//
//  Full-window review: shows the same fit grid used by the preview area (MacFitGridView),
//  but covering the entire window. The previous implementation lives in ReviewViewOld.swift.
//

import SwiftUI

#if os(macOS)
struct ReviewView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var viewModel: ReviewViewModel

    @FocusState private var isFocused: Bool
    @State private var panPosition = CGPoint(x: 0.5, y: 0.5)
    @State private var viewport = CGSize(width: 1, height: 1)
    @State private var isMinimapActive = false

    init(appState: AppState, viewModel: ReviewViewModel) {
        self.appState = appState
        self.viewModel = viewModel
    }

    var body: some View {
        MacFitGridView(photos: viewModel.photos,
                       cacheManager: viewModel.previewsManager,
                       isZoomed: viewModel.isZoomed,
                       fullResImages: viewModel.fullResImages,
                       panPosition: panPosition,
                       isPanLocked: isMinimapActive,
                       onPanChanged: { panPosition = $0 },
                       onViewportChanged: { if viewport != $0 { viewport = $0 } },
                       onHoverChanged: { viewModel.hoveredPhotoId = $0?.id },
                       onRatingChanged: { viewModel.handleRating($1, for: $0) },
                       onApprove: { viewModel.handleApprove(for: $0) },
                       onReject: { viewModel.handleToggleDelete(for: $0) },
                       onRemove: { viewModel.handleRemove(for: $0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemeColors.panelBackground)
            .overlay(alignment: .bottomTrailing) {
                if viewModel.isZoomed,
                   let first = viewModel.photos.first,
                   let image = viewModel.fullResImages[first.path] {
                    ZoomMinimapView(image: image, viewport: viewport, position: $panPosition,
                                    isInteracting: $isMinimapActive)
                        .padding(12)
                }
            }
            .overlay(alignment: .top) {
                // Sits in the (hidden) title bar area, next to the traffic lights
                topBar
                    .ignoresSafeArea(edges: .top)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(phases: .down) { _ in
                // Shortcuts from Settings > Shortcuts
                guard let event = NSApp.currentEvent,
                      let action = ShortcutStore.shared.action(for: event) else {
                    return .ignored
                }
                switch action {
                    case .zoom:    viewModel.toggleZoom()
                    case .approve: viewModel.approveTargets()
                    case .reject:  viewModel.toggleDeleteTargets()
                    case .review:  appState.reviewGroup = nil
                    default:       return .ignored
                }
                return .handled
            }
            .onKeyPress(.escape) {
                appState.reviewGroup = nil
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: " ")) { _ in
                appState.reviewGroup = nil
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "12345")) { press in
                guard let rating = Int(String(press.characters)) else {
                    return .ignored
                }
                viewModel.rateTargets(rating)
                return .handled
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
            .background(KeyEventInterceptor(onLeft: viewModel.navigateLeft,
                                            onRight: viewModel.navigateRight))
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.reviewGroup = nil
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .help("Close review")

            if viewModel.showsPagination {
                HStack(spacing: 8) {
                    Button(action: viewModel.navigateLeft) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!viewModel.canNavigateLeft)

                    Text(viewModel.paginationText)
                        .font(.callout.monospacedDigit())

                    Button(action: viewModel.navigateRight) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!viewModel.canNavigateRight)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
                .help("Previous / next")
            }

            Spacer()

            Button(action: viewModel.toggleZoom) {
                Label(viewModel.isZoomed ? "Fit" : "Zoom 100%",
                      systemImage: viewModel.isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                    .font(.callout)
                    .foregroundColor(viewModel.isZoomed ? .accentColor : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .help("Toggle 100% zoom (Z)")
        }
        .padding(.leading, 84) // room for the window traffic lights
        .padding(.trailing, 12)
        .padding(.top, 12)
        .frame(height: 48)
    }
}
#else
typealias ReviewView = ReviewViewOld
#endif
