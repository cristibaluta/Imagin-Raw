//
//  LargePreviewView.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct LargePreviewView: View {
    let photo: PhotoItem
    @State private var preview: NSImage?
    @State private var isLoading = false
    @State private var exifData: [String: Any]?

    var body: some View {
        ZStack {
            // Background layer - ensures full view coverage
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Main image view
            if let nsImage = preview {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                Text("Failed to load image")
                    .foregroundColor(.secondary)
            }

            // Overlay positioned using stacks and spacers
            VStack {
                Spacer() // Push content to bottom

                HStack {
                    // EXIF overlay in bottom left
                    if let exifData = exifData {
                        CompactExifOverlayView(exifData: exifData)
                    }

                    Spacer() // Push overlay to left
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            loadPreview()
        }
        .onChange(of: photo) { _, _ in
            loadPreview()
        }
    }

    private func loadPreview() {
        guard preview == nil else { return }

        isLoading = true
        exifData = nil // Reset EXIF data

        Task.detached(priority: .userInitiated) {
            let (loadedImage, extractedExifData) = await loadImageWithExif(from: photo.path)

            await MainActor.run {
                self.preview = loadedImage
                self.exifData = extractedExifData
                self.isLoading = false
            }
        }
    }

    private func loadImageWithExif(from path: String) async -> (NSImage?, [String: Any]?) {
        let url = URL(fileURLWithPath: path)
        let fileExtension = url.pathExtension.lowercased()

        // Define RAW file extensions
        let rawExtensions = ["arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
                           "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
                           "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
                           "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"]

        if rawExtensions.contains(fileExtension) {
            // Load RAW file using new RawPhoto method
            print("Loading RAW preview for: \(path)")
            guard let rawPhoto = RawWrapper.shared().extractRawPhoto(path) else {
                print("Failed to extract RawPhoto from: \(path)")
                return (nil, nil)
            }

            // Store EXIF data for display
            var exifInfo: [String: Any]? = nil
            if let exifData = rawPhoto.exifData {
                print("=== EXIF Data for \(url.lastPathComponent) ===")
                for (key, value) in exifData {
                    print("\(key): \(value)")
                }
                print("=== End EXIF Data ===")
                exifInfo = exifData as? [String: Any]
            } else {
                print("No EXIF data found for: \(path)")
            }

            // Return the image and EXIF data
            guard let imageData = rawPhoto.imageData else {
                print("No image data in RawPhoto for: \(path)")
                return (nil, exifInfo)
            }

            return (NSImage(data: imageData), exifInfo)
        } else {
            // Load regular image file directly from disk
            print("Loading image preview for: \(path)")
            return (NSImage(contentsOfFile: path), nil)
        }
    }
}

struct ExifOverlayView: View {
    let exifData: [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Camera Info")
                .font(.headline)
                .foregroundColor(.white)

            // Camera details
            if let make = exifData["Make"] as? String,
               let model = exifData["Model"] as? String {
                Text("\(make) \(model)")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }

            if let lens = exifData["LensModel"] as? String {
                Text("Lens: \(lens)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }

            Divider()
                .background(Color.white.opacity(0.5))

            // Shooting parameters
            HStack(spacing: 16) {
                if let iso = exifData["ISO"] as? NSNumber {
                    Text("ISO \(iso)")
                        .font(.caption)
                        .foregroundColor(.white)
                }

                if let aperture = exifData["Aperture"] as? NSNumber {
                    Text("f/\(String(format: "%.1f", aperture.doubleValue))")
                        .font(.caption)
                        .foregroundColor(.white)
                }

                if let shutter = exifData["ShutterSpeed"] as? NSNumber {
                    let shutterValue = shutter.doubleValue
                    if shutterValue < 1 {
                        Text("1/\(Int(round(1/shutterValue)))s")
                            .font(.caption)
                            .foregroundColor(.white)
                    } else {
                        Text("\(String(format: "%.1f", shutterValue))s")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }

            if let focal = exifData["FocalLength"] as? NSNumber {
                Text("\(String(format: "%.0f", focal.doubleValue))mm")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }

            // Image dimensions
            if let width = exifData["ImageWidth"] as? NSNumber,
               let height = exifData["ImageHeight"] as? NSNumber {
                Text("\(width) × \(height)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }

            // Date/time if available
            if let dateTime = exifData["DateTime"] as? Date {
                Text(dateTime, style: .date)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }

            // GPS if available
            if let gps = exifData["GPS"] as? [String: Any],
               let lat = gps["Latitude"] as? NSNumber,
               let lng = gps["Longitude"] as? NSNumber {
                Text("GPS: \(String(format: "%.4f", lat.doubleValue)), \(String(format: "%.4f", lng.doubleValue))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
        .padding(16)
        .frame(maxWidth: 250, alignment: .leading)
    }
}

struct CompactExifOverlayView: View {
    let exifData: [String: Any]

    var body: some View {
        // LEFT PANEL
        VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 16) {
                // Aperture
                if let aperture = exifData["Aperture"] as? NSNumber {
                    Text("ƒ/\(String(format: "%.1f", aperture.doubleValue))")
                }
                // Shutter speed
                if let shutter = exifData["ShutterSpeed"] as? NSNumber {
                    let shutterValue = shutter.doubleValue
                    if shutterValue < 1 {
                        Text("1/\(Int(round(1/shutterValue)))s")
                    } else {
                        Text("\(String(format: "%.1f", shutterValue))s")
                    }
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)

            HStack(spacing: 10) {

                // Focal Length
                if let focal = exifData["FocalLength"] as? NSNumber {
                    Text("\(String(format: "%.0f", focal.doubleValue))mm")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                        )
                }

                // ISO
                if let iso = exifData["ISO"] as? NSNumber {
                    Text("ISO \(iso)")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
        )
        .padding(16)
    }
}
