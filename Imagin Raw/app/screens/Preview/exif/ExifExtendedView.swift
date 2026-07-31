//
//  ExifExtendedView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 27.07.2026.
//

import SwiftUI

struct ExifExtendedView: View {

    let exifData: ExifData
    let fileSize: Int64?
    let dateCreated: Date?

    @Binding var gridType: GridType

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if gridType == .large {
                VStack(alignment: .leading, spacing: 8) {
                    CameraDetailsView(exifData: exifData)
                    LensDetailsView(exifData: exifData)
                }
                .padding(.top, 4)
                .padding(.bottom, 0)
                .padding(.leading, 8)
            } else {
                HStack(spacing: 8) {
                    CameraDetailsView(exifData: exifData)
                    LensDetailsView(exifData: exifData)
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
                if let w = exifData.width, let h = exifData.height {
                    divider
                    exifItem(label: "\(w) x \(h)")
                }

                // Date & time
                if let date = exifData.dateCaptured {
                    divider
                    exifItem(label: date.exifDateString)
//                } else if let date = dateCreated {
//                    divider
//                    HStack {
//                        exifItem(label: date.exifDateString)
//                        Image(systemName: "info.circle")
//                            .foregroundColor(.gray)
//                            .help("This is the date the file was created on disk, not when it was taken.")
//
//                    }
                } else {
                    divider
                    exifItem(label: "--")
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
