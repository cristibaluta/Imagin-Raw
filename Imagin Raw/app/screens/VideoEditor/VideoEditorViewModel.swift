//
//  VideoEditorViewModel.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 02.07.2026.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class VideoEditorViewModel: ObservableObject {

    // MARK: - Published state
    @Published private(set) var images: [IRImage] = []
    @Published private(set) var isLoadingImages = false
    @Published var fps: Double = 10
    @Published var quality: Double = 1.0  // 0.0 (lowest) → 1.0 (highest)
    @Published private(set) var isPlaying = false
    @Published private(set) var currentFrameIndex: Int = 0
    @Published private(set) var isExporting = false
    @Published private(set) var exportProgress: Double = 0
    @Published var exportError: String? = nil
    @Published var showExportPanel = false
    @Published private(set) var exportedURL: URL? = nil

    // MARK: - Private
    private let photos: [PhotoItem]
    private let cacheManager: PhotoCacheManager
    private var playbackTimer: Timer?

    let minFPS: Double = 1
    let maxFPS: Double = 30

    init(photos: [PhotoItem], cacheManager: PhotoCacheManager) {
        self.photos = photos
        self.cacheManager = cacheManager
    }

    // MARK: - Image loading

    func loadImages() {
        guard images.isEmpty else { return }
        isLoadingImages = true
        Task {
            var loaded: [IRImage] = []
            for photo in photos {
                if let img = await cacheManager.getImage(for: photo) {
                    loaded.append(img)
                }
            }
            self.images = loaded
            self.isLoadingImages = false
        }
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard images.count > 1 else { return }
        isPlaying = true
        let interval = 1.0 / fps
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentFrameIndex = (self.currentFrameIndex + 1) % self.images.count
            }
        }
    }

    func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Export

    func exportVideo(to outputURL: URL) {
        guard !images.isEmpty else { return }
        stopPlayback()
        isExporting = true
        exportProgress = 0
        exportError = nil
        exportedURL = nil

        let capturedImages = images
        let capturedFPS = fps
        let capturedQuality = quality

        // Write to a temp file first, then move to the user-chosen URL.
        // AVAssetWriter cannot write directly to a security-scoped fileExporter URL on macOS Sequoia.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        Task.detached(priority: .userInitiated) {
            do {
                try await Self.buildVideo(images: capturedImages, fps: capturedFPS, quality: capturedQuality, tempURL: tempURL) { progress in
                    Task { @MainActor in
                        self.exportProgress = progress
                    }
                }
                // Move temp file → final destination
                _ = outputURL.startAccessingSecurityScopedResource()
                defer { outputURL.stopAccessingSecurityScopedResource() }
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.moveItem(at: tempURL, to: outputURL)
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 1
                    self.exportedURL = outputURL
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - AVFoundation video building

    private static func buildVideo(images: [IRImage],
                                   fps: Double,
                                   quality: Double,
                                   tempURL: URL,
                                   progress: @Sendable @escaping (Double) -> Void) async throws {

        // Pick the largest frame size from all images, capped to 1920×1920
        let maxDim: CGFloat = 1920
        var videoSize = CGSize(width: 1280, height: 720)
        for img in images {
            let s = img.size
            if s.width > 0 && s.height > 0 {
                videoSize = s
                break
            }
        }
        // Scale down if needed
        if videoSize.width > maxDim || videoSize.height > maxDim {
            let scale = maxDim / max(videoSize.width, videoSize.height)
            videoSize = CGSize(width: round(videoSize.width * scale),
                               height: round(videoSize.height * scale))
        }
        // Force even dimensions (required by H.264)
        videoSize = CGSize(width: CGFloat(Int(videoSize.width) & ~1),
                           height: CGFloat(Int(videoSize.height) & ~1))

        try? FileManager.default.removeItem(at: tempURL)

        // Map quality (0–1) to an H.264 average bitrate.
        // 0 → ~2 Mbps, 0.5 → ~10 Mbps, 1.0 → ~40 Mbps
        let minBitrate: Double = 2_000_000
        let maxBitrate: Double = 40_000_000
        let bitrate = minBitrate + (maxBitrate - minBitrate) * quality

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Int(videoSize.width)),
            AVVideoHeightKey: NSNumber(value: Int(videoSize.height)),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: NSNumber(value: bitrate),
                AVVideoMaxKeyFrameIntervalKey: NSNumber(value: Int(fps)),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(videoSize.width),
            kCVPixelBufferHeightKey as String: Int(videoSize.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                          sourcePixelBufferAttributes: attributes)
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "VideoEditor", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to start"])
        }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let total = images.count

        for (i, image) in images.enumerated() {
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            guard let pixelBuffer = pixelBuffer(from: image, size: videoSize) else { continue }
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            progress(Double(i + 1) / Double(total))
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .failed, let error = writer.error {
            throw error
        }
    }

    private static func pixelBuffer(from image: IRImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width), Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }

        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                   width: Int(size.width),
                                   height: Int(size.height),
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }

        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        #if os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return buffer }
        #else
        guard let cgImage = image.cgImage else { return buffer }
        #endif

        // Letterbox: fit image inside size preserving aspect ratio
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        guard imgW > 0, imgH > 0 else { return buffer }
        let scale = min(size.width / imgW, size.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawRect = CGRect(x: (size.width - drawW) / 2,
                              y: (size.height - drawH) / 2,
                              width: drawW,
                              height: drawH)
        ctx.draw(cgImage, in: drawRect)

        return buffer
    }
}
