//
//  ExifBarView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.03.2026.
//

import SwiftUI

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
}()

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
                exifItem(label: dateFormatter.string(from: date))
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

// MARK: Extended view

struct ExifExtendedView: View {
    let exifData: ExifData
    let fileSize: Int64?
    let dateCreated: Date?
    let width: Int?
    let height: Int?
    @Binding var gridType: ThumbGridViewModel.GridType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if gridType == .large {
                VStack(alignment: .leading, spacing: 8) {
                    Exif1View(exifData: exifData)
                    Exif2View(exifData: exifData)
                }
                .padding(.top, 4)
                .padding(.bottom, 0)
                .padding(.leading, 8)
            } else {
                HStack(spacing: 8) {
                    Exif1View(exifData: exifData)
                    Exif2View(exifData: exifData)
                }
                .padding(.top, 4)
                .padding(.bottom, 0)
                .padding(.leading, 8)
            }

            Spacer()

            HStack {
                // File size
                if let size = fileSize {
                    exifItem(label: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }

                // Resolution
                if let w = width, let h = height {
                    divider
                    exifItem(label: "\(w) x \(h)")
                }

                // Date & time
                if let date = dateCreated {
                    divider
                    exifItem(label: dateFormatter.string(from: date))
                }
            }
            .padding(.leading, 8)
            .padding(.bottom, 12)
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

struct Exif1View: View {
    let exifData: ExifData

    private var shutterText: String? {
        guard let shutter = exifData.shutterSpeed else {
            return nil
        }
        return shutter < 1 ? "1/\(Int(round(1/shutter)))s" : "\(String(format: "%.1f", shutter))s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                // Aperture
                if let aperture = exifData.aperture {
                    Text("ƒ/\(String(format: "%.1f", aperture))")
                }
                // Shutter speed
                if let shutter = shutterText {
                    Text(shutter)
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.white)

            HStack(spacing: 10) {
                // ISO
                if let iso = exifData.iso {
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
    let exifData: ExifData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Camera details
            if let make = exifData.cameraMake, let model = exifData.cameraModel {
                Text("\(make) \(model)")
            }
            HStack {
                // Lens
                if let lens = exifData.lensModel {
                    Text(lens)
                }
                // Focal Length
                if let focal = exifData.lensFocalLength {
                    Text("\(String(format: "%.0f", focal))mm")
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.primary.opacity(0.2))
                        )
                }
            }
        }
        .font(.system(size: 12))
        .padding(.vertical, 4)
    }
}
