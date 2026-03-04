//
//  LargePreviewView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI
import ImageIO

struct LargePreviewView: View {
    let photo: PhotoItem
    @StateObject private var model = LargePreviewViewModel()

    var body: some View {
        ZStack {
            // Background layer - ensures full view coverage
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Main image view
            if let nsImage = model.preview {
                if model.alignToTopLeft {
                    HStack {
                        VStack {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .padding(2)
                            Spacer()
                        }
                        Spacer()
                    }
                } else {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                }
            } else if model.isLoading {
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
                        model.toggleAlignment()
                    }) {
                        Image(systemName: model.alignToTopLeft ? "arrow.down.right.square" : "arrow.up.left.square")
                            .font(.title2)
                            .foregroundColor(model.alignToTopLeft ? .white.opacity(0.4) : .white)
                            .padding()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(model.alignToTopLeft ? "Center image" : "Align to top-left")

                    Spacer() // Push button to left
                }

                Spacer() // Push content to bottom

                HStack {
                    // EXIF overlay positioning based on photo alignment
                    if model.alignToTopLeft {
                        Spacer() // Push overlay to right
                        if let nsImage = model.preview, let exifData = model.exifData {
                            CompactExifOverlayView(nsImage: nsImage, exifData: exifData)
                        }
                    } else {
                        // EXIF overlay in bottom left when photo is centered
                        if let nsImage = model.preview, let exifData = model.exifData {
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
            model.setPhoto(photo)
        }
        .onChange(of: photo) { _, newPhoto in
            model.setPhoto(newPhoto)
        }
    }
}

struct CompactExifOverlayView: View {
    let nsImage: NSImage
    let exifData: [String: Any]

    var body: some View {
        if nsImage.size.width > nsImage.size.height {
            HStack(spacing: 8) {
                Exif1View(exifData: exifData)
                Exif2View(exifData: exifData)
            }
            .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 4) {
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
            .font(.system(size: 12))
            .foregroundColor(.white)

            HStack(spacing: 10) {
                // ISO
                if let iso = exifData["ISO"] as? NSNumber {
                    Text("ISO \(iso)")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
            }
            .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
        )
    }
}

struct Exif2View: View {
    let exifData: [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                                .fill(.primary.opacity(0.4))
                        )
                }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.7), lineWidth: 2)
        )
    }
}
