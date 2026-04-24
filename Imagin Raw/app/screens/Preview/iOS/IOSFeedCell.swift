//
//  IOSFeedCell.swift
//  Imagin Raw
//
//  Instagram-style feed cell.
//  Owns one LargePreviewViewModel — same pattern as LargePreviewView on macOS.
//

#if os(iOS)
import UIKit
import Combine

final class IOSFeedCell: UICollectionViewCell {
    static let identifier = "IOSFeedCell"
    static let exifCardHeight: CGFloat = 86

    // MARK: - Views
    private let imageView     = UIImageView()
    private let spinner       = UIActivityIndicatorView(style: .large)
    private let exifCard      = UIView()
    private let filenameLabel = UILabel()
    private let dateLabel     = UILabel()
    private let exposureLabel = UILabel()
    private let lensLabel     = UILabel()

    // MARK: - ViewModel  (one per cell, lives as long as the cell)
    private let viewModel = PreviewViewModel()
    private var cancellables = Set<AnyCancellable>()

    private(set) var currentPath: String?

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        bindViewModel()
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

    // Bind once at init — no need to rebind on reuse since the VM is permanent.
    private func bindViewModel() {
        viewModel.$preview
            .receive(on: DispatchQueue.main)
            .sink { [weak self] img in self?.imageView.image = img }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                loading ? self?.spinner.startAnimating() : self?.spinner.stopAnimating()
            }
            .store(in: &cancellables)

        viewModel.$exifInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] exif in self?.applyExif(exif) }
            .store(in: &cancellables)
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height
        let exifH = Self.exifCardHeight
        let imgH  = max(0, h - exifH)

        imageView.frame = CGRect(x: 0, y: 0, width: w, height: imgH)
        spinner.center  = CGPoint(x: w / 2, y: imgH / 2)
        exifCard.frame  = CGRect(x: 0, y: imgH, width: w, height: exifH)

        let pad: CGFloat = 14
        let lineH: CGFloat = 18
        let inner = w - pad * 2
        var y: CGFloat = 10

        let dateSz = dateLabel.sizeThatFits(CGSize(width: inner / 2, height: lineH))
        let dateW  = min(dateSz.width, inner * 0.45)
        dateLabel.frame     = CGRect(x: w - pad - dateW, y: y, width: dateW,             height: lineH)
        filenameLabel.frame = CGRect(x: pad,             y: y, width: inner - dateW - 6, height: lineH)
        y += lineH + 5
        exposureLabel.frame = CGRect(x: pad, y: y, width: inner, height: lineH)
        y += lineH + 5
        lensLabel.frame     = CGRect(x: pad, y: y, width: inner, height: lineH)
    }

    // MARK: - Configure
    func configure(with photo: PhotoItem) {
        guard currentPath != photo.path else { return }
        currentPath = photo.path

        // Static fields — available immediately
        var line1: [String] = [URL(fileURLWithPath: photo.path).lastPathComponent]
        if let pw = photo.width, let ph = photo.height, pw > 0 { line1.append("\(pw)×\(ph)") }
        if let b = photo.fileSizeBytes { line1.append(ByteCountFormatter.string(fromByteCount: b, countStyle: .file)) }
        filenameLabel.text = line1.joined(separator: "  ·  ")

        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        dateLabel.text = df.string(from: photo.dateCreated)

        exposureLabel.text = nil
        lensLabel.text = nil
        imageView.image = nil

        // Hand off to the VM — it loads preview + exif and publishes via Combine
        viewModel.setPhoto(photo)
    }

    // MARK: - EXIF
    private func applyExif(_ exif: ExifInfo?) {
        var exp: [String] = []
        if let ap = exif?.aperture     { exp.append("ƒ/\(String(format:"%.1f", ap))") }
        if let ss = exif?.shutterSpeed { exp.append(ss < 1 ? "1/\(Int(round(1/ss)))s" : "\(String(format:"%.1f",ss))s") }
        if let iso = exif?.iso         { exp.append("ISO \(iso)") }
        if let fl = exif?.focalLength  { exp.append("\(String(format:"%.0f",fl)) mm") }
        exposureLabel.text = exp.isEmpty ? nil : exp.joined(separator: "  •  ")

        var lens: [String] = []
        if let l  = exif?.lensModel   { lens.append(l) }
        lensLabel.text = lens.isEmpty ? nil : lens.joined(separator: "  •  ")
    }

    // MARK: - Reuse
    override func prepareForReuse() {
        super.prepareForReuse()
        currentPath = nil
        imageView.image = nil
        spinner.stopAnimating()
        filenameLabel.text = nil
        dateLabel.text = nil
        exposureLabel.text = nil
        lensLabel.text = nil
    }
}
#endif
