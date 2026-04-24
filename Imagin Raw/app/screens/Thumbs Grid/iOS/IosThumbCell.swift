//
//  IosThumbCell.swift
//  Imagin Raw
//
//  UICollectionViewCell equivalent of ThumbCollectionItem for iOS.
//

import Foundation
#if os(iOS)
import UIKit

final class IosThumbCell: UICollectionViewCell {
    static let identifier = "IosThumbCell"

    // MARK: - Views
    private let thumbView        = UIImageView()
    private let filenameLabel    = UILabel()
    private let selectionBorder  = UIView()
    private let trashOverlay     = UIImageView()
    private let acrBadge         = UIView()
    private let acrIcon          = UIImageView()
    private let jpgBadge         = UILabel()
    private let jpgBadgeView     = UIView()
    private var starStack        = UIStackView()
    private let checkmarkView    = UIImageView()

    // MARK: - State
    private(set) var currentPath: String?
    private var currentPhoto: PhotoItem?
    private var callbacks: ThumbCellCallbacks?
    private var itemSize: CGFloat = 100
    private var isSelectMode: Bool = false
    private weak var thumbsManager: ThumbsManager!
    var onSelectFromHere: (() -> Void)?
    var onEndSelection: (() -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGestures()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.backgroundColor = UIColor(white: 0.15, alpha: 1)

        thumbView.contentMode = .scaleAspectFit
        thumbView.clipsToBounds = true
        contentView.addSubview(thumbView)

        selectionBorder.layer.borderColor = UIColor.systemBlue.cgColor
        selectionBorder.layer.borderWidth = 0
        selectionBorder.isUserInteractionEnabled = false
        contentView.addSubview(selectionBorder)

        trashOverlay.image = UIImage(systemName: "xmark")
        trashOverlay.tintColor = .orange
        trashOverlay.contentMode = .scaleAspectFit
        trashOverlay.isHidden = true
        contentView.addSubview(trashOverlay)

        acrIcon.image = UIImage(systemName: "slider.horizontal.3")
        acrIcon.tintColor = .white
        acrIcon.contentMode = .scaleAspectFit
        acrBadge.backgroundColor = UIColor.gray
        acrBadge.layer.cornerRadius = 3
        acrBadge.clipsToBounds = true
        acrBadge.addSubview(acrIcon)
        acrBadge.isHidden = true
        contentView.addSubview(acrBadge)

        jpgBadge.text = "+JPG"
        jpgBadge.font = UIFont.boldSystemFont(ofSize: 8)
        jpgBadge.textColor = .white
        jpgBadge.textAlignment = .center
        jpgBadgeView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        jpgBadgeView.layer.cornerRadius = 3
        jpgBadgeView.clipsToBounds = true
        jpgBadgeView.addSubview(jpgBadge)
        jpgBadgeView.isHidden = true
        contentView.addSubview(jpgBadgeView)

        filenameLabel.font = UIFont.systemFont(ofSize: 11)
        filenameLabel.textColor = .label
        filenameLabel.textAlignment = .center
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(filenameLabel)

        starStack.axis = .horizontal
        starStack.spacing = 2
        starStack.alignment = .center
        starStack.distribution = .fillEqually
        starStack.isHidden = true
        for i in 1...5 {
            let btn = UIButton(type: .system)
            btn.tag = i
            btn.setImage(UIImage(systemName: "star"), for: .normal)
            btn.tintColor = .systemYellow
            btn.addTarget(self, action: #selector(starTapped(_:)), for: .touchUpInside)
            starStack.addArrangedSubview(btn)
        }
        contentView.addSubview(starStack)

        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold))
        checkmarkView.tintColor = .white
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.isHidden = true
        checkmarkView.layer.shadowColor = UIColor.black.cgColor
        checkmarkView.layer.shadowOpacity = 0.5
        checkmarkView.layer.shadowRadius = 3
        checkmarkView.layer.shadowOffset = .zero
        contentView.addSubview(checkmarkView)
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        contentView.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        contentView.addGestureRecognizer(longPress)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height

        // Image fills the entire cell — no title area
        thumbView.frame = CGRect(x: 0, y: 0, width: w, height: h)
        selectionBorder.frame = contentView.bounds

        let iconSize: CGFloat = 24
        trashOverlay.frame = CGRect(x: (w - iconSize) / 2, y: (h - iconSize) / 2,
                                    width: iconSize, height: iconSize)

        let badgeH: CGFloat = 18
        let badgeW: CGFloat = 22
        let badgePad: CGFloat = 4
        jpgBadgeView.frame = CGRect(x: w - badgeW - badgePad, y: badgePad, width: badgeW, height: badgeH)
        jpgBadge.frame = jpgBadgeView.bounds
        acrBadge.frame = CGRect(x: jpgBadgeView.frame.minX - badgeW - 2, y: badgePad, width: badgeW, height: badgeH)
        acrIcon.frame = acrBadge.bounds.insetBy(dx: 2, dy: 2)

        filenameLabel.isHidden = true
        starStack.isHidden = true

        let checkSize: CGFloat = 26
        checkmarkView.frame = CGRect(x: w - checkSize - 6, y: h - checkSize - 6,
                                     width: checkSize, height: checkSize)
    }

    // MARK: - Configure

    var thumbImage: IRImage? { thumbView.image }

    func setThumb(_ image: IRImage) {
        thumbView.image = image
    }

    func configure(with photo: PhotoItem,
                   isSelected: Bool,
                   isSelectMode: Bool,
                   itemSize: CGFloat,
                   thumbsManager: ThumbsManager,
                   priority: ThumbnailRequest.Priority = .high,
                   callbacks: ThumbCellCallbacks) {
        self.callbacks = callbacks
        self.itemSize = itemSize
        self.thumbsManager = thumbsManager
        self.isSelectMode = isSelectMode

        let pathChanged = currentPath != photo.path
        currentPath = photo.path
        currentPhoto = photo

        if pathChanged {
            thumbView.image = nil

            let path = photo.path
            if let cached = thumbsManager.getCachedThumbnail(for: photo) {
                thumbView.image = cached
            } else {
                thumbsManager.loadThumbnail(for: photo, priority: priority) { [weak self] image in
                    guard self?.currentPath == path else {
                        return
                    }
                    self?.thumbView.image = image
                }
            }
        }

        updateSelection(isSelected: isSelected, isSelectMode: isSelectMode)
        trashOverlay.isHidden = !photo.toDelete
        acrBadge.isHidden = !photo.hasACR
        jpgBadgeView.isHidden = !(photo.isRawFile && photo.hasJPG)
        filenameLabel.text = URL(fileURLWithPath: photo.path).lastPathComponent
        applyLabelStyle(for: photo)
        updateStars(for: photo)
    }

    func updateSelection(isSelected: Bool, isSelectMode: Bool = false) {
        selectionBorder.layer.borderWidth = 0
        if isSelectMode {
            thumbView.alpha = isSelected ? 0.7 : 1.0
            checkmarkView.isHidden = !isSelected
        } else {
            thumbView.alpha = 1.0
            checkmarkView.isHidden = true
        }
    }

    // MARK: - Stars

    private func updateStars(for photo: PhotoItem) {
        guard photo.isRawFile else {
            starStack.isHidden = true
            return
        }
        let rating = currentRating(for: photo)
        for case let btn as UIButton in starStack.arrangedSubviews {
            let filled = btn.tag <= rating
            btn.setImage(UIImage(systemName: filled ? "star.fill" : "star"), for: .normal)
        }
        starStack.isHidden = rating == 0
    }

    @objc private func starTapped(_ sender: UIButton) {
        guard let photo = currentPhoto else { return }
        callbacks?.onRatingChanged(photo, sender.tag)
    }

    // MARK: - Gestures

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let photo = currentPhoto else { return }
        callbacks?.onTap(photo, .none)
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        guard let photo = currentPhoto else { return }
        callbacks?.onDoubleClick(photo)
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let photo = currentPhoto else { return }
        showContextMenu(for: photo, sourceView: contentView)
    }

    private func showContextMenu(for photo: PhotoItem, sourceView: UIView) {
        guard let vc = parentViewController else { return }

        let sheet = UIAlertController(title: URL(fileURLWithPath: photo.path).lastPathComponent,
                                      message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Review Photos", style: .default) { [weak self] _ in
            self?.callbacks?.onReviewSelected(photo)
        })
        sheet.addAction(UIAlertAction(title: "Select from here", style: .default) { [weak self] _ in
            self?.onSelectFromHere?()
        })
        if isSelectMode {
            sheet.addAction(UIAlertAction(title: "End Selection", style: .default) { [weak self] _ in
                self?.onEndSelection?()
            })
        }
        sheet.addAction(UIAlertAction(title: "Copy to...", style: .default) { [weak self] _ in
            self?.callbacks?.onCopyTo(photo)
        })
        sheet.addAction(UIAlertAction(title: "Rename...", style: .default) { [weak self] _ in
            self?.callbacks?.onRenameTo(photo)
        })
        sheet.addAction(UIAlertAction(title: "Move to Trash", style: .destructive) { [weak self] _ in
            self?.callbacks?.onMoveToTrash(photo)
        })
        if photo.toDelete, let info = callbacks?.onMoveAllMarkedToTrash(photo) {
            sheet.addAction(UIAlertAction(title: "Move to Trash all Rejected Photos (\(info.count))",
                                          style: .destructive) { _ in info.action() })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sourceView
            pop.sourceRect = sourceView.bounds
        }
        vc.present(sheet, animated: true)
    }

    // MARK: - Helpers

    private func currentRating(for photo: PhotoItem) -> Int {
        if let r = photo.xmp?.rating, r > 0 { return r }
        return photo.inCameraRating ?? 0
    }

    private func applyLabelStyle(for photo: PhotoItem) {
        if photo.toDelete {
            filenameLabel.backgroundColor = UIColor.orange
            filenameLabel.textColor = .black
            return
        }
        guard let label = photo.xmp?.label, !label.isEmpty else {
            filenameLabel.backgroundColor = .clear
            filenameLabel.textColor = .label
            return
        }
        switch label {
        case "Select":   filenameLabel.backgroundColor = .systemRed;    filenameLabel.textColor = .white
        case "Second":   filenameLabel.backgroundColor = .systemYellow; filenameLabel.textColor = .black
        case "Approved": filenameLabel.backgroundColor = UIColor(red: 133/255, green: 199/255, blue: 102/255, alpha: 1); filenameLabel.textColor = .black
        case "Review":   filenameLabel.backgroundColor = .systemBlue;   filenameLabel.textColor = .white
        case "To Do":    filenameLabel.backgroundColor = .systemPurple; filenameLabel.textColor = .white
        default:         filenameLabel.backgroundColor = .clear;        filenameLabel.textColor = .label
        }
    }

    private var parentViewController: UIViewController? {
        var r: UIResponder? = self
        while let next = r?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            r = next
        }
        return nil
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        currentPath = nil
        currentPhoto = nil
        thumbView.image = nil
        selectionBorder.layer.borderWidth = 0
        trashOverlay.isHidden = true
        acrBadge.isHidden = true
        jpgBadgeView.isHidden = true
        starStack.isHidden = true
        filenameLabel.backgroundColor = .clear
        filenameLabel.textColor = .label
    }
}
#endif
