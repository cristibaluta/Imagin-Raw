//
//  CameraDetailsView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 27.07.2026.
//

import SwiftUI

struct CameraDetailsView: View {
    let exifData: ExifData

    private var shutterText: String? {
        guard let shutter = exifData.shutterSpeed else {
            return "--"
        }
        return shutter < 1
            ? "1/\(Int(round(1/shutter)))s"
            : "\(String(format: "%.1f", shutter))s"
    }

    private var expCompText: String? {
        guard let comp = exifData.exposureCompensation else {
            return "--"
        }
        return comp < 0
            ? "-\(String(format: "%.1f", abs(comp)))"
            : (comp > 0 ? "+\(String(format: "%.1f", abs(comp)))" : "0 EV")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                // Aperture
                if let aperture = exifData.aperture {
                    Text("ƒ/\(String(format: "%.1f", aperture))")
                } else {
                    Text("ƒ/--")
                }
                // ISO
                if let iso = exifData.iso {
                    Text("ISO \(iso)")
                } else {
                    Text("ISO --")
                }
            }
            .foregroundColor(.white)

            HStack(spacing: 16) {
                // Shutter speed
                if let shutterText {
                    Text(shutterText)
                }
                // Exposure compensation
                if let expCompText {
                    Text(expCompText)
                }
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.35))
        )
    }
}
