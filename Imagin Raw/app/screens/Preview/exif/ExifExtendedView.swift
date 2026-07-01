import SwiftUI

struct ExifExtendedView: View {
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Exif1View(exifInfo: exifInfo)
                Exif2View(exifInfo: exifInfo)
            }
            .padding(.top, 4)
            .padding(.bottom, 0)
            .padding(.leading, 8)

            HStack {
                // File size
                if let size = fileSize {
                    exifItem(label: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }

                // Date & time
                if let date = dateCreated {
                    divider
                    exifItem(label: Self.dateFormatter.string(from: date))
                }
            }
//            .frame(height: 16)
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
    let exifInfo: ExifInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                // Aperture
                if let aperture = exifInfo.aperture {
                    Text("ƒ/\(String(format: "%.1f", aperture))")
                }
                // Shutter speed
                if let shutter = exifInfo.shutterSpeed {
                    let shutterValue = shutter
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
                if let iso = exifInfo.iso {
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
    let exifInfo: ExifInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Camera details
            if let make = exifInfo.cameraMake, let model = exifInfo.cameraModel {
                Text("\(make) \(model)")
            }
            HStack {
                if let lens = exifInfo.lensModel {
                    Text(lens)
                }
                // Focal Length
                if let focal = exifInfo.focalLength {
                    Text("\(String(format: "%.0f", focal))mm")
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
    }
}
