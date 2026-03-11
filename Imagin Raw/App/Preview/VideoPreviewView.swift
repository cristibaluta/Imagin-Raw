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
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var volume: Double = 1.0
    @State private var isMuted = false
    @State private var timeObserver: Any?

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
                .onAppear { setupPlayer() }
                .onDisappear { teardownPlayer() }

            // Bottom bar — same height as photo preview bar
            HStack(spacing: 0) {
                // Play / Pause
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
                .help(isPlaying ? "Pause" : "Play")

                // Rewind to start
                Button(action: { seek(to: 0) }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Rewind to start")

                // Scrubber
                Slider(value: $currentTime, in: 0...max(duration, 1), onEditingChanged: { editing in
                    if !editing {
                        seek(to: currentTime)
                    }
                })
                .controlSize(.small)
                .padding(.horizontal, 8)

                // Time label
                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: 80)

                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1, height: 14)

                // Mute / Volume
                Button(action: { isMuted.toggle(); player.isMuted = isMuted }) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 4)
                .help(isMuted ? "Unmute" : "Mute")
            }
            .frame(height: 40)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onChange(of: photo) { _, newPhoto in
            switchVideo(to: newPhoto)
        }
    }

    // MARK: - Player setup

    private func setupPlayer() {
        // Observe duration
        if let item = player.currentItem {
            Task {
                let dur = try? await item.asset.load(.duration)
                if let d = dur, d.isValid, !d.isIndefinite {
                    duration = d.seconds
                }
            }
        }

        // Periodic time observer — updates scrubber every 0.1s
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
        }

        // Auto-reset when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
            seek(to: 0)
        }
    }

    private func teardownPlayer() {
        player.pause()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func switchVideo(to newPhoto: PhotoItem) {
        teardownPlayer()
        player = AVPlayer(url: URL(fileURLWithPath: newPhoto.path))
        isPlaying = false
        currentTime = 0
        duration = 0
        setupPlayer()
    }

    // MARK: - Controls

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            // If at end, rewind first
            if currentTime >= duration - 0.1 {
                seek(to: 0)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }
}
