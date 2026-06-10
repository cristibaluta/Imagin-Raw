//
//  VideoPreviewView.swift
//  Imagin Raw
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoPreviewView: NSViewRepresentable {
    let photo: PhotoItem

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: URL(fileURLWithPath: photo.path))
        playerView.player?.play()
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        // Only swap the player if the photo actually changed
        let newURL = URL(fileURLWithPath: photo.path)
        guard ((playerView.player?.currentItem?.asset as? AVURLAsset) != nil),
              (playerView.player?.currentItem?.asset as? AVURLAsset)?.url != newURL
        else {
            return
        }

        playerView.player?.pause()
        playerView.player = AVPlayer(url: newURL)
        playerView.player?.play()
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: ()) {
        playerView.player?.pause()
        playerView.player = nil
    }
}

// This crashes on Tahoe if the build is made from Sequoia

//struct VideoPreviewView: View {
//    let photo: PhotoItem
//
//    @State private var player: AVPlayer
//
//    init(photo: PhotoItem) {
//        self.photo = photo
//        let p = AVPlayer(url: URL(fileURLWithPath: photo.path))
//        _player = State(initialValue: p)
//    }
//
//    var body: some View {
//        VideoPlayer(player: player)
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .onDisappear {
//            teardownPlayer()
//        }
//        .onChange(of: photo) { _, newPhoto in
//            switchVideo(to: newPhoto)
//        }
//    }
//
//    private func teardownPlayer() {
//        player.pause()
//    }
//
//    private func switchVideo(to newPhoto: PhotoItem) {
//        teardownPlayer()
//        player = AVPlayer(url: URL(fileURLWithPath: newPhoto.path))
//    }
//}
