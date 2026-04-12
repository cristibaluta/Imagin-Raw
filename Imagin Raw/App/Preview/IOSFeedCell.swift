//
//  IOSFeedCell.swift
//  Imagin Raw
//
//  Instagram-style feed cell for iOS preview.
//  Full-width image on top, EXIF info below.
//

#if os(iOS)
import UIKit
import Photos

final class IOSFeedCell: UICollectionViewCell {
    static let identifier = "IOSFeedCell"

    // MARK: - Views
    private let imageView   = UIImageView()
    private let spinner     = UIActivityIndicatorView(style: .medium)
    private let exifCard    = UIView()

    // EXIF labels
    private let filenameLabel   = UILabel()
    private let cameraLabel     = UILabel()
    private let exposureLabel   = UILabel()
    private let focalLabel      = UILabel()
    private let lensLabel       = UILabel()
    private let dateLabel       = UILabel()
    private let sizeLabel       = UILabel()

    // MARK: - State
    private(set) var currentPath: String?

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup
    private func setupViews() {
        contentView.backgroundColor = .black

        // Image
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        contentView.addSubview(imageView)

        // Spinner
        spinner.color = .lightGray
        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)

        // EXIF card
        exifCard.backgroundColor = UIColor(white: 0.1, alpha: 1)
        contentView.addSubview(exifCard)

        // Filename (bold header)
        filenameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        filenameLabel.textColor = .white
        filenameLabel.lineBreakMode = .byTruncatingMiddle

        // Exposure row
        exposureLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        exposureLabel.textColor = UIColor(white: 0.85, alpha: 1)

        // Focal length
        focalLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        focalLabel.textColor = UIColor(white: 0.85, alpha: 1)

        // Lens
        lensLabel.font = .systemFont(ofSize: 11)
        lensLabel.textColor = UIColor(white: 0.6, alpha: 1)
        lensLabel.lineBreakMode = .byTruncatingTail

        // Camera
        cameraLabel.font = .systemFont(ofSize: 11)
        cameraLabel.textColor = UIColor(white: 0.6, alpha: 1)

        // Date
        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = UIColor(white: 0.5, alpha: 1)

        // Size
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = UIColor(white: 0.5, alpha: 1)

        [filenameLabel, exposureLabel, focalLabel, lensLabel, cameraLabel, dateLabel, sizeLabel].forEach {
            exifCard.addSubview($0)
        }
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height

        let exifH = IOSFeedCell.exifHeight
        let imgH = h - exifH

        imageView.frame = CGRect(x: 0, y: 0, width: w, height: imgH)
        spinner.center = CGPoint(x: w / 2, y: imgH / 2)
        exifCard.frame = CGRect(x: 0, y: imgH, width: w, height: exifH)

        let pad: CGFloat = 14
        let lineH: CGFloat = 18
        var y: CGFloat = 12

        filenameLabel.frame = CGRect(x: pad, y: y, width: w - pad * 2, height: lineH)
        y += lineH + 6

        exposureLabel.frame = CGRect(x: pad, y: y, width: w - pad * 2, height: lineH)
        y += lineH + 2

        focalLabel.frame = CGRect(x: pad, y: y, width: w / 2 - pad, height: lineH)
        sizeLabel.frame  = CGRect(x: w / 2, y: y, width: w / 2 - pad, height: lineH)
        y += lineH + 2

        lensLabel.frame   = CGRect(x: pad, y: y, width: w - pad * 2, height: lineH)
        y += lineH + 2

        cameraLabel.frame = CGRect(x: pad, y: y, width: w - pad * 2, height: lineH)
        y += lineH + 2

        dateLabel.frame   = CGRect(x: pad, y: y, width: w - pad * 2, height: lineH)
    }

    // MARK: - Configure
    func configure(with photo: PhotoItem) {
        let pathChanged = currentPath != photo.path
        currentPath = photo.path

        if pathChanged {
            imageView.image = nil
            spinner.startAnimating()

            let path = photo.path
            if let cached = ThumbsManager.shared.getCachedThumbnail(for: path) {
                imageView.image = cached
                spinner.stopAnimating()
            }
            // Load full preview (replaces thumb when ready)
            PreviewsManager.shared.loadPreview(for: photo) { [weak self] image, exifInfo in
                guard self?.currentPath == path else { return }
                if let image = image {
                    self?.imageView.image = image
                }
                self?.spinner.stopAnimating()
                if let exifInfo = exifInfo {
                    self?.applyExif(exifInfo, photo: photo)
                }
            }
        }

        applyExifFromPhoto(photo)
    }

    // MARK: - EXIF population

    /// Immediately populate what we already know from the PhotoItem (no async needed).
    private func applyExifFromPhoto(_ photo: PhotoItem) {
        filenameLabel.text = URL(fileURLWithPath: photo.path).lastPathComponent

        // Camera
        let make = photo.cameraMake ?? ""
        let model = photo.cameraModel ?? ""
        let camera = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
        cameraLabel.text = camera.isEmpty ? nil : camera

        // Date
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        dateLabel.text = df.string(from: photo.dateCreated)

        // File size
        if let bytes = photo.fileSizeBytes {
            sizeLabel.text = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } else {
            sizeLabel.text = nil
        }

        // Exposure from PhotoItem (XMP)
        exposureLabel.text = nil
        focalLabel.text = nil
        lensLabel.text = nil
    }

    /// Apply richer EXIF data once PreviewsManager delivers it.
    private func applyExif(_ exif: ExifInfo, photo: PhotoItem) {
        // Exposure row: ƒ/x.x  1/xxxs  ISO xxxx
        var parts: [String] = []
        if let ap = exif.aperture { parts.append("ƒ/\(String(format: "%.1f", ap))") }
        if let ss = exif.shutterSpeed {
            parts.append(ss < 1 ? "1/\(Int(round(1/ss)))s" : "\(String(format:"%.1f",ss))s")
        }
        if let iso = exif.iso { parts.append("ISO \(iso)") }
        exposureLabel.text = parts.joined(separator: "  ")

        if let fl = exif.focalLength { focalLabel.text = "\(String(format:"%.0f",fl))mm" }
        if let lens = exif.lensModel { lensLabel.text = lens }

        let make = exif.cameraMake ?? photo.cameraMake ?? ""
        let model = exif.cameraModel ?? photo.cameraModel ?? ""
        let cam = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
        cameraLabel.text = cam.isEmpty ? nil : cam
    }

    // MARK: - Sizing

    /// Fixed height reserved for the EXIF card below the image.
    static let exifHeight: CGFloat = 160

    /// Total cell height: square image + EXIF card.
    static func cellHeight(for width: CGFloat) -> CGFloat {
        width + exifHeight
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        currentPath = nil
        imageView.image = nil
        spinner.stopAnimating()
        filenameLabel.text = nil
        cameraLabel.text = nil
        exposureLabel.text = nil
        focalLabel.text = nil
        lensLabel.text = nil
        dateLabel.text = nil
        sizeLabel.text = nil
    }
}
#endif
