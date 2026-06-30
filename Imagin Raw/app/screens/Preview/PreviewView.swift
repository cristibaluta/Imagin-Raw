//
//  LargePreviewView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct PreviewView: View {

    @ObservedObject var viewModel: PreviewViewModel

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
            if let photo = viewModel.photo {
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
