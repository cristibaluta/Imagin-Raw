//
//  IOSFeedCell.swift
//  Imagin Raw
//
//  Instagram-style feed cell for iOS preview.
//  Full-width photo + EXIF card below. Sized by sizeForItemAt — no Auto Layout.
//

#if os(iOS)
import UIKit
import Photos
import ImageIO

final class IOSFeedCell: UICollectionViewCell {
    static let identifier = "IOSFeedCell"

    /// Fixed height of the EXIF card.
    static let exifCardHeight: CGFloat = 86

    // MARK: - Views
    private let imageView = UIImageView()
    private let spinner   = UIActivityIndicatorView(style: .large)
    private let exifCard  = UIView()

    // Line 1 – left: filename · resolution · size    right: date
    private let filenameLabel   = UILabel()
    private let dateLabel       = UILabel()
    // Line 2 – aperture / shutter / ISO
    private let exposureLabel   = UILabel()
    // Line 3 – lens + focal length
    private let lensLabel       = UILabel()

    // MARK: - State
    private(set) var currentPath: String?
    private var currentPhoto: PhotoItem?

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup
    private func setupViews() {
        contentView.backgroundColor = .black

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        contentView.addSubview(imageView)

        spinner.color = .lightGray
        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)

        exifCard.backgroundColor = UIColor(white: 0.10, alpha: 1)
        contentView.addSubview(exifCard)

        filenameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        filenameLabel.textColor = .white
        filenameLabel.numberOfLines = 1
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        exifCard.addSubview(filenameLabel)

        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = UIColor(white: 0.55, alpha: 1)
        dateLabel.numberOfLines = 1
        dateLabel.textAlignment = .right
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        exifCard.addSubview(dateLabel)

        exposureLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        exposureLabel.textColor = UIColor(white: 0.75, alpha: 1)
        exposureLabel.numberOfLines = 1
        exifCard.addSubview(exposureLabel)

        lensLabel.font = .systemFont(ofSize: 11)
        lensLabel.textColor = UIColor(white: 0.55, alpha: 1)
        lensLabel.numberOfLines = 1
        lensLabel.lineBreakMode = .byTruncatingTail
        exifCard.addSubview(lensLabel)
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height
        let exifH = Self.exifCardHeight
        let imgH = max(0, h - exifH)

        imageView.frame = CGRect(x: 0, y: 0, width: w, height: imgH)
        spinner.center  = CGPoint(x: w / 2, y: imgH / 2)
        exifCard.frame  = CGRect(x: 0, y: imgH, width: w, height: exifH)

        let pad: CGFloat = 14
        let lineH: CGFloat = 18
        let inner = w - pad * 2
        var y: CGFloat = 10

        // Line 1: filename (left, truncated) + date (right, fixed width)
        let dateSz = dateLabel.sizeThatFits(CGSize(width: inner / 2, height: lineH))
        let dateW  = min(dateSz.width, inner * 0.45)
        dateLabel.frame    = CGRect(x: w - pad - dateW, y: y, width: dateW, height: lineH)
        filenameLabel.frame = CGRect(x: pad, y: y, width: inner - dateW - 6, height: lineH)
        y += lineH + 5

        // Line 2: exposure
        exposureLabel.frame = CGRect(x: pad, y: y, width: inner, height: lineH)
        y += lineH + 5

        // Line 3: lens + focal length
        lensLabel.frame = CGRect(x: pad, y: y, width: inner, height: lineH)
    }

    // MARK: - Configure
    func configure(with photo: PhotoItem) {
        let pathChanged = currentPath != photo.path
        currentPath = photo.path
        currentPhoto = photo

        guard pathChanged else { return }

        imageView.image = nil
        spinner.startAnimating()
        populateExif(exifInfo: nil, photo: photo)

        let path = photo.path
        if let cached = ThumbsManager.shared.getCachedThumbnail(for: path) {
            imageView.image = cached
        }

        PreviewsManager.shared.loadPreview(for: photo) { [weak self] image, _ in
            guard let self, self.currentPath == path else { return }
            if let image { self.imageView.image = image }
            self.spinner.stopAnimating()
        }

        // Load EXIF independently — PreviewsManager never delivers it
        Task.detached(priority: .utility) { [weak self] in
            let exif = await Self.loadExif(for: photo)
            guard let self else { return }
            await MainActor.run {
                guard self.currentPath == path else { return }
                self.populateExif(exifInfo: exif, photo: photo)
            }
        }
    }

    private static func loadExif(for photo: PhotoItem) async -> ExifInfo? {
#if canImport(Photos)
        // PhotoKit — extract from PHAsset
        if let asset = photo.phAsset {
            return await withCheckedContinuation { cont in
                let opts = PHContentEditingInputRequestOptions()
                opts.isNetworkAccessAllowed = true
                asset.requestContentEditingInput(with: opts) { input, _ in
                    guard let url = input?.fullSizeImageURL,
                          let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
                    else { cont.resume(returning: nil); return }
                    cont.resume(returning: ExifInfo.from(imageProperties: props))
                }
            }
        }
#endif
        // File-based
        let url = URL(fileURLWithPath: photo.path)
        let ext = url.pathExtension.lowercased()
        if FilesExtensions.raw.contains(ext) {
            guard let raw = RawWrapper.shared().extractRawPhoto(photo.path),
                  let dict = raw.exifData as? [String: Any] else { return nil }
            return ExifInfo.from(rawExif: dict)
        } else {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            else { return nil }
            return ExifInfo.from(imageProperties: props)
        }
    }

    // MARK: - EXIF
    private func populateExif(exifInfo: ExifInfo?, photo: PhotoItem) {
        // Line 1 left: "FILENAME  1234×5678  4.2 MB"
        var line1Parts = [URL(fileURLWithPath: photo.path).lastPathComponent]
        if let pw = photo.width, let ph = photo.height, pw > 0 {
            line1Parts.append("\(pw)×\(ph)")
        }
        if let bytes = photo.fileSizeBytes {
            line1Parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        filenameLabel.text = line1Parts.joined(separator: "  ·  ")

        // Line 1 right: date
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        dateLabel.text = df.string(from: photo.dateCreated)

        // Line 2: ƒ/1.8  1/1000s  ISO 400
        var exp: [String] = []
        if let ap = exifInfo?.aperture { exp.append("ƒ/\(String(format:"%.1f",ap))") }
        if let ss = exifInfo?.shutterSpeed {
            exp.append(ss < 1 ? "1/\(Int(round(1/ss)))s" : "\(String(format:"%.1f",ss))s")
        }
        if let iso = exifInfo?.iso { exp.append("ISO \(iso)") }
        exposureLabel.text = exp.isEmpty ? nil : exp.joined(separator: "   ")

        // Line 3: lens name  ·  focal length
        var lensParts: [String] = []
        if let lens = exifInfo?.lensModel { lensParts.append(lens) }
        if let fl = exifInfo?.focalLength { lensParts.append("\(String(format:"%.0f",fl)) mm") }
        lensLabel.text = lensParts.isEmpty ? nil : lensParts.joined(separator: "  ·  ")
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        currentPath = nil
        currentPhoto = nil
        imageView.image = nil
        spinner.stopAnimating()
        filenameLabel.text = nil
        dateLabel.text = nil
        exposureLabel.text = nil
        lensLabel.text = nil
    }
}
#endif
