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
    @State private var alignToTopLeft = UserDefaults.standard.bool(forKey: "ImageAlignmentTopLeft")

    var body: some View {
        ZStack {
            // Background layer - ensures full view coverage
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Main image view
            if let nsImage = preview {
                if alignToTopLeft {
                    HStack {
                        VStack {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .padding()
                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else if isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                Text("Failed to load image")
                    .foregroundColor(.secondary)
            }

            // Overlay positioned using stacks and spacers
            VStack {
                // Top overlay with alignment button
                HStack {
                    Button(action: {
                        alignToTopLeft.toggle()
                        UserDefaults.standard.set(alignToTopLeft, forKey: "ImageAlignmentTopLeft")
                    }) {
                        Image(systemName: alignToTopLeft ? "arrow.down.right.square" : "arrow.up.left.square")
                            .font(.title2)
                            .foregroundColor(alignToTopLeft ? .white.opacity(0.4) : .white)
                            .padding()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(alignToTopLeft ? "Center image" : "Align to top-left")

                    Spacer() // Push button to left
                }

                Spacer() // Push content to bottom

                HStack {
                    // EXIF overlay positioning based on photo alignment
                    if alignToTopLeft {
                        Spacer() // Push overlay to right
                        if let nsImage = preview, let exifData = exifData {
                            CompactExifOverlayView(nsImage: nsImage, exifData: exifData)
                        }
                    } else {
                        // EXIF overlay in bottom left when photo is centered
                        if let nsImage = preview, let exifData = exifData {
                            CompactExifOverlayView(nsImage: nsImage, exifData: exifData)
                        }
                        Spacer() // Push overlay to left
                    }
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

struct CompactExifOverlayView: View {
    let nsImage: NSImage
    let exifData: [String: Any]

    var body: some View {
        if nsImage.size.width > nsImage.size.height {
            HStack(spacing: 16) {
                Exif1View(exifData: exifData)
                Exif2View(exifData: exifData)
            }
            .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Exif1View(exifData: exifData)
                Exif2View(exifData: exifData)
            }
            .padding(16)
        }
    }
}

struct Exif1View: View {
    let exifData: [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

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
    }
}

struct Exif2View: View {
    let exifData: [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Camera details
            if let make = exifData["Make"] as? String,
               let model = exifData["Model"] as? String {
                Text("\(make) \(model)")
            }

            HStack {
                if let lens = exifData["LensModel"] as? String {
                    Text(lens)
                }

                // Focal Length
                if let focal = exifData["FocalLength"] as? NSNumber {
                    Text("\(String(format: "%.0f", focal.doubleValue))mm")
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.7))
                        )
                }
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.7), lineWidth: 2)
        )
    }
}

//// Image dimensions
//if let width = exifData["ImageWidth"] as? NSNumber,
//   let height = exifData["ImageHeight"] as? NSNumber {
//    Text("\(width) × \(height)")
//        .font(.caption2)
//        .foregroundColor(.white.opacity(0.8))
//}
//
//// Date/time if available
//if let dateTime = exifData["DateTime"] as? Date {
//    Text(dateTime, style: .date)
//        .font(.caption2)
//        .foregroundColor(.white.opacity(0.8))
//}
//
//// GPS if available
//if let gps = exifData["GPS"] as? [String: Any],
//   let lat = gps["Latitude"] as? NSNumber,
//   let lng = gps["Longitude"] as? NSNumber {
//    Text("GPS: \(String(format: "%.4f", lat.doubleValue)), \(String(format: "%.4f", lng.doubleValue))")
//        .font(.caption2)
//        .foregroundColor(.white.opacity(0.8))
//}
