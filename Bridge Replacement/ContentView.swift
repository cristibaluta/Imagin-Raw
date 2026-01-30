//
//  ContentView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 29.01.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    var body: some View {
        NavigationSplitView {
            // Left sidebar: folders
            SidebarView(model: model)
        } content: {
            // Middle: thumbnails
            ThumbGridView(photos: model.photos, model: model)
        } detail: {
            // Right: large preview
            if let photo = model.selectedPhoto {
                LargePreviewView(photo: photo)
                    .id(photo.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                Text("Select a photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 1200, minHeight: 700)
        .preferredColorScheme(.dark)
    }
}
