//
//  ExifBarView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 10.03.2026.
//

import SwiftUI

struct LensDetailsView: View {
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
