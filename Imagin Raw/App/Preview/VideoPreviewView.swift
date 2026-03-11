//
//  VideoPreviewView.swift
//  Imagin Raw
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoPreviewView: View {
    let photo: PhotoItem

    @State private var player: AVPlayer

    init(photo: PhotoItem) {
        self.photo = photo
        let p = AVPlayer(url: URL(fileURLWithPath: photo.path))
        _player = State(initialValue: p)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Video area
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDisappear {
                    teardownPlayer()
                }

            // Bottom bar — same height as photo preview bar
            HStack(spacing: 0) {

            }
            .frame(height: 40)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onChange(of: photo) { _, newPhoto in
            switchVideo(to: newPhoto)
        }
    }

    private func teardownPlayer() {
        player.pause()
    }

    private func switchVideo(to newPhoto: PhotoItem) {
        teardownPlayer()
        player = AVPlayer(url: URL(fileURLWithPath: newPhoto.path))
    }
}
