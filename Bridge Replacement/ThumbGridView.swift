//
//  ThumbGridView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct ThumbGridView: View {
    let photos: [PhotoItem]
    @ObservedObject var model: BrowserModel
    @FocusState private var isFocused: Bool

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let columnsCount = 3

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos) { photo in
                    ThumbCell(path: photo.path, isSelected: model.selectedPhoto?.id == photo.id)
                        .frame(width: 100, height: 150)
                        .onTapGesture {
                            model.selectedPhoto = photo
                        }
                }
            }
            .padding()
        }
        .frame(width: 300+60)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .onAppear {
            isFocused = true
            // Auto-select first photo when photos change
            if model.selectedPhoto == nil && !photos.isEmpty {
                model.selectedPhoto = photos.first
            }
        }
        .onChange(of: photos) { _, newPhotos in
            // Auto-select first photo when folder changes
            if !newPhotos.isEmpty {
                model.selectedPhoto = newPhotos.first
            }
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard !photos.isEmpty else { return .ignored }

        let currentIndex = photos.firstIndex { $0.id == model.selectedPhoto?.id } ?? 0
        var newIndex = currentIndex

        switch keyPress.key {
        case .leftArrow:
            newIndex = max(0, currentIndex - 1)
        case .rightArrow:
            newIndex = min(photos.count - 1, currentIndex + 1)
        case .upArrow:
            newIndex = max(0, currentIndex - columnsCount)
        case .downArrow:
            newIndex = min(photos.count - 1, currentIndex + columnsCount)
        default:
            return .ignored
        }

        if newIndex != currentIndex {
            model.selectedPhoto = photos[newIndex]
            return .handled
        }

        return .ignored
    }
}
