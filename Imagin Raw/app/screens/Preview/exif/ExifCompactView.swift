//
//  ExifCompactView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 27.07.2026.
//

import SwiftUI

struct ExifCompactView: View {
    let exifData: ExifData
    var fileSize: Int64?
    var dateCreated: Date?

    private var shutterText: String? {
        guard let shutter = exifData.shutterSpeed else {
            return nil
        }
        return shutter < 1
            ? "1/\(Int(round(1/shutter)))s"
            : "\(String(format: "%.1f", shutter))s"
    }

    var body: some View {
        HStack(spacing: 0) {
            if exifData.aperture != nil || shutterText != nil || exifData.iso != nil || exifData.lensFocalLength != nil {
                HStack {
                    // Aperture
                    if let aperture = exifData.aperture {
                        exifItem(label: "ƒ/\(String(format: "%.1f", aperture))")
                    }
                    // Shutter
                    if let shutter = shutterText {
                        exifItem(label: shutter)
                    }
                    // ISO
                    if let iso = exifData.iso {
                        exifItem(label: "ISO \(iso)")
                    }
                    // Focal length
                    if let focal = exifData.lensFocalLength {
                        divider
                        exifItem(label: "\(String(format: "%.0f", focal))mm")
                    }
                }
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, 8)
            }

            if exifData.cameraModel != nil || exifData.lensModel != nil {
                HStack {
                    // Camera
                    if let model = exifData.cameraModel {
                        let make = exifData.cameraMake ?? ""
                        exifItem(label: "\(make) \(model)".trimmingCharacters(in: .whitespaces))
                    }
                    // Lens
                    if let lens = exifData.lensModel {
                        divider
                        exifItem(label: lens)
                    }
                }
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, 8)
            }

            // File size
            if let size = fileSize {
                exifItem(label: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }

            // Date & time
            if let date = dateCreated {
                divider
                exifItem(label: date.exifDateString)
            }

            Spacer()
        }
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
