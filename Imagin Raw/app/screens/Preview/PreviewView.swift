//
//  LargePreviewView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct PreviewView: View {

    @ObservedObject var viewModel: PreviewViewModel
    var videoEditorPhotos: [PhotoItem]?
    var pdfEditorPhotos: [PhotoItem]?
    var albumName: String = ""
    var previewsCacheManager: PhotoCacheManager
    var onDismissVideoEditor: (() -> Void)?
    var onDismissPDFEditor: (() -> Void)?

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)

            // Content
            if let photos = videoEditorPhotos, photos.count >= 2 {
                VideoEditorView(photos: photos, cacheManager: previewsCacheManager, onDismiss: onDismissVideoEditor)
                    .id(photos.map(\.id).hashValue)
            } else if let photos = pdfEditorPhotos, photos.count >= 1 {
                PDFEditorView(photos: photos, albumName: albumName, cacheManager: previewsCacheManager, onDismiss: onDismissPDFEditor)
                    .id(photos.map(\.id).hashValue)
            } else if let photo = viewModel.photo {
                if photo.isVideo {
                    VideoPreviewView(photo: photo)
                } else {
                    PhotoPreviewView(photo: photo, viewModel: viewModel)
                }
            } else {
                ShortcutsHelpView()
            }
        }
    }
}
