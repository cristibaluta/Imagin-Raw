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
        VideoPlayer(player: player)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            teardownPlayer()
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
