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
    var dateCreated: Date?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var shutterText: String? {
        guard let shutter = exifInfo.shutterSpeed else { return nil }
        return shutter < 1 ? "1/\(Int(round(1/shutter)))s" : "\(String(format: "%.1f", shutter))s"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                // Aperture
                if let aperture = exifInfo.aperture {
                    exifItem(label: "ƒ/\(String(format: "%.1f", aperture))")
                }
                // Shutter
                if let shutter = shutterText {
                    exifItem(label: shutter)
                }
                // ISO
                if let iso = exifInfo.iso {
                    exifItem(label: "ISO \(iso)")
                }
            }
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .padding(.horizontal, 8)

            HStack {
                // Focal length
                if let focal = exifInfo.focalLength {
                    exifItem(label: "\(String(format: "%.0f", focal))mm")
                    divider
                }
                // Lens
                if let lens = exifInfo.lensModel {
                    exifItem(label: lens)
                }
            }
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .padding(.horizontal, 8)

            // Camera
            if let model = exifInfo.cameraModel {
                let make = exifInfo.cameraMake ?? ""
                exifItem(label: "\(make) \(model)".trimmingCharacters(in: .whitespaces))
            }

            // File size
            if let size = fileSize {
                divider
                exifItem(label: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }

            // Date & time
            if let date = dateCreated {
                divider
                exifItem(label: Self.dateFormatter.string(from: date))
            }

            Spacer()
        }
        .frame(height: 40)
        .background(Color(IRColor.controlBackgroundColor))
    }

    private func exifItem(label: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundColor(.primary)
            .lineLimit(1)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 4)
    }
}

// MARK: - Vertical EXIF layout for 4/5-column grid

struct ExifColumnView: View {
    let exifInfo: ExifInfo
    var fileSize: Int64?
    var dateCreated: Date?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var shutterText: String? {
        guard let shutter = exifInfo.shutterSpeed else { return nil }
        return shutter < 1 ? "1/\(Int(round(1/shutter)))s" : "\(String(format: "%.1f", shutter))s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Aperture / Shutter / ISO grouped in rounded border
            let hasExposure = exifInfo.aperture != nil || shutterText != nil || exifInfo.iso != nil
            if hasExposure {
                HStack(spacing: 6) {
                    if let aperture = exifInfo.aperture {
                        exifItem(label: "ƒ/\(String(format: "%.1f", aperture))")
                    }
                    if let shutter = shutterText {
                        exifItem(label: shutter)
                    }
                    if let iso = exifInfo.iso {
                        exifItem(label: "ISO \(iso)")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                )
            }

            // Focal length
            if let focal = exifInfo.focalLength {
                exifItem(label: "\(String(format: "%.0f", focal))mm")
            }

            // Lens
            if let lens = exifInfo.lensModel {
                exifItem(label: lens)
            }

            // Camera
            if let model = exifInfo.cameraModel {
                let make = exifInfo.cameraMake ?? ""
                exifItem(label: "\(make) \(model)".trimmingCharacters(in: .whitespaces))
            }

            // File size
            if let size = fileSize {
                exifItem(label: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }

            // Date & time
            if let date = dateCreated {
                exifItem(label: Self.dateFormatter.string(from: date))
            }
        }
        .padding(8)
    }

    private func exifItem(label: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundColor(.primary)
            .lineLimit(1)
    }
}
