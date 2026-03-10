//
//  ExifBarView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.03.2026.
//

import SwiftUI

struct ExifBarView: View {
    let exifInfo: ExifInfo
    var fileSize: Int64?

    private var shutterText: String? {
        guard let shutter = exifInfo.shutterSpeed else { return nil }
        return shutter < 1 ? "1/\(Int(round(1/shutter)))s" : "\(String(format: "%.1f", shutter))s"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Aperture
            if let aperture = exifInfo.aperture {
                exifItem(label: "ƒ/\(String(format: "%.1f", aperture))")
                divider
            }
            // Shutter
            if let shutter = shutterText {
                exifItem(label: shutter)
                divider
            }
            // ISO
            if let iso = exifInfo.iso {
                exifItem(label: "ISO \(iso)")
                divider
            }
            // Focal length
            if let focal = exifInfo.focalLength {
                exifItem(label: "\(String(format: "%.0f", focal))mm")
                divider
            }
            // Camera
            if let model = exifInfo.cameraModel {
                let make = exifInfo.cameraMake ?? ""
                exifItem(label: "\(make) \(model)".trimmingCharacters(in: .whitespaces))
                divider
            }
            // Lens
            if let lens = exifInfo.lensModel {
                exifItem(label: lens)
                if fileSize != nil { divider }
            }
            // File size
            if let size = fileSize {
                exifItem(label: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }

            Spacer()
        }
        .frame(height: 40)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func exifItem(label: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 14)
    }
}
