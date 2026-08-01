//
//  LargePreviewView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct PreviewView: View {

    @ObservedObject var viewModel: PreviewViewModel

    var albumName: String = ""
    var previewsCacheManager: PhotoCacheManager

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
            if let photos = viewModel.photos {

                if viewModel.showVideoEditor {
                    VideoEditorView(photos: photos, cacheManager: previewsCacheManager, onDismiss: {
                        viewModel.showVideoEditor = false
                    })
                    .id(photos.map(\.id).hashValue)
                }
                else if viewModel.showPDFEditor {
                    PDFEditorView(photos: photos, albumName: albumName, cacheManager: previewsCacheManager, onDismiss: {
                        viewModel.showPDFEditor = false
                    })
                    .id(photos.map(\.id).hashValue)
                }
                else {
                    if photos.first?.isVideo == true {
                        VideoPreviewView(photo: photos.first!)
                    } else {
                        if viewModel.photos?.count ?? 0 > 1 {
                            PhotosPreviewView(viewModel: viewModel)
                        } else {
                            PhotoPreviewView(viewModel: viewModel)
                        }
                    }
                }
            } else {
                ShortcutsHelpView()
            }
        }
    }
}
