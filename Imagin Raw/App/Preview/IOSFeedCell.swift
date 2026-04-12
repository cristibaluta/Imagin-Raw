//
//  IOSFeedCell.swift
//  Imagin Raw
//
//  Instagram-style feed cell for iOS preview.
//  Full-width photo + EXIF card below. Sized by sizeForItemAt — no Auto Layout.
//

#if os(iOS)
import UIKit

final class IOSFeedCell: UICollectionViewCell {
    static let identifier = "IOSFeedCell"

    /// Fixed height of the EXIF card. Keep in sync with populateExif row count.
    static let exifCardHeight: CGFloat = 220

    // MARK: - Views
    private let imageView = UIImageView()
    private let spinner   = UIActivityIndicatorView(style: .large)
    private let exifCard  = UIView()
    private let exifStack = UIStackView()

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

        exifStack.axis = .vertical
        exifStack.spacing = 6
        exifStack.alignment = .fill
        exifCard.addSubview(exifStack)
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

        let pad: CGFloat = 16
        exifStack.frame = CGRect(x: pad, y: 12, width: w - pad * 2, height: exifH - 24)
    }

    // MARK: - Configure
    func configure(with photo: PhotoItem) {
        let pathChanged = currentPath != photo.path
        currentPath = photo.path
        currentPhoto = photo

        if pathChanged {
            imageView.image = nil
            spinner.startAnimating()

            let path = photo.path
            if let cached = ThumbsManager.shared.getCachedThumbnail(for: path) {
                imageView.image = cached
            }
            PreviewsManager.shared.loadPreview(for: photo) { [weak self] image, exifInfo in
                guard let self, self.currentPath == path else { return }
                if let image { self.imageView.image = image }
                self.spinner.stopAnimating()
                if let exifInfo { self.populateExif(exifInfo: exifInfo, photo: photo) }
            }
        }
        populateExif(exifInfo: nil, photo: photo)
    }

    // MARK: - EXIF
    private func populateExif(exifInfo: ExifInfo?, photo: PhotoItem) {
        exifStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Filename
        addRow(icon: "doc.fill",
               text: URL(fileURLWithPath: photo.path).lastPathComponent,
               font: .systemFont(ofSize: 13, weight: .semibold), color: .white)

        addSpacer(4)

        // Exposure
        var exp: [String] = []
        if let ap = exifInfo?.aperture { exp.append("ƒ/\(String(format:"%.1f",ap))") }
        if let ss = exifInfo?.shutterSpeed {
            exp.append(ss < 1 ? "1/\(Int(round(1/ss)))s" : "\(String(format:"%.1f",ss))s")
        }
        if let iso = exifInfo?.iso { exp.append("ISO \(iso)") }
        if !exp.isEmpty {
            addRow(icon: "camera.aperture",
                   text: exp.joined(separator: "   "),
                   font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                   color: UIColor(white: 0.9, alpha: 1))
        }

        // Focal length
        if let fl = exifInfo?.focalLength {
            addRow(icon: "scope",
                   text: "\(String(format:"%.0f",fl)) mm",
                   font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                   color: UIColor(white: 0.85, alpha: 1))
        }

        // Lens
        if let lens = exifInfo?.lensModel {
            addRow(icon: "eyeglasses",
                   text: lens,
                   font: .systemFont(ofSize: 12), color: UIColor(white: 0.7, alpha: 1))
        }

        // Camera
        let make  = exifInfo?.cameraMake  ?? photo.cameraMake  ?? ""
        let model = exifInfo?.cameraModel ?? photo.cameraModel ?? ""
        let cam   = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
        if !cam.isEmpty {
            addRow(icon: "camera",
                   text: cam,
                   font: .systemFont(ofSize: 12), color: UIColor(white: 0.7, alpha: 1))
        }

        // Divider
        addDivider()

        // Dimensions
        if let pw = photo.width, let ph = photo.height, pw > 0 {
            let mp = Double(pw * ph) / 1_000_000
            addRow(icon: "aspectratio",
                   text: "\(pw) × \(ph)  (\(String(format:"%.1f",mp)) MP)",
                   font: .systemFont(ofSize: 12), color: UIColor(white: 0.6, alpha: 1))
        }

        // File size
        if let bytes = photo.fileSizeBytes {
            addRow(icon: "internaldrive",
                   text: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file),
                   font: .systemFont(ofSize: 12), color: UIColor(white: 0.6, alpha: 1))
        }

        // Date
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        addRow(icon: "calendar",
               text: df.string(from: photo.dateCreated),
               font: .systemFont(ofSize: 12), color: UIColor(white: 0.6, alpha: 1))
    }

    // MARK: - Row helpers
    private func addRow(icon: String, text: String, font: UIFont, color: UIColor) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        let img = UIImageView(image: UIImage(systemName: icon))
        img.tintColor = color.withAlphaComponent(0.55)
        img.contentMode = .scaleAspectFit
        img.setContentHuggingPriority(.required, for: .horizontal)
        img.widthAnchor.constraint(equalToConstant: 16).isActive = true
        img.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let lbl = UILabel()
        lbl.text = text
        lbl.font = font
        lbl.textColor = color
        lbl.numberOfLines = 1
        lbl.lineBreakMode = .byTruncatingTail

        row.addArrangedSubview(img)
        row.addArrangedSubview(lbl)
        exifStack.addArrangedSubview(row)
    }

    private func addSpacer(_ h: CGFloat) {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        exifStack.addArrangedSubview(v)
    }

    private func addDivider() {
        let v = UIView()
        v.backgroundColor = UIColor(white: 1, alpha: 0.08)
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        exifStack.addArrangedSubview(v)
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        currentPath = nil
        currentPhoto = nil
        imageView.image = nil
        spinner.stopAnimating()
        exifStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
}
#endif
