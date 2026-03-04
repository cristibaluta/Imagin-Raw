import SwiftUI

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
