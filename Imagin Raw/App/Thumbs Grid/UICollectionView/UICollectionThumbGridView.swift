//
//  UICollectionThumbGridView.swift
//  Imagin Raw
//
//  UICollectionView-based photo grid for iOS — mirrors CollectionThumbGridView (macOS).
//

import SwiftUI
#if os(iOS)
import UIKit

// MARK: - Section Header (Duplicate Groups)

final class UIDuplicateSectionHeader: UICollectionReusableView {
    static let identifier = "UIDuplicateSectionHeader"

    private let pill      = UIView()
    private let label     = UILabel()
    private let reviewBtn = UIButton(type: .system)
    private var onReview: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        pill.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        pill.layer.cornerRadius = 4
        addSubview(pill)

        label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        pill.addSubview(label)

        reviewBtn.setTitle("Review", for: .normal)
        reviewBtn.titleLabel?.font = UIFont.systemFont(ofSize: 10)
        reviewBtn.backgroundColor = UIColor.systemBlue
        reviewBtn.layer.cornerRadius = 3
        reviewBtn.setTitleColor(.white, for: .normal)
        reviewBtn.addTarget(self, action: #selector(reviewTapped), for: .touchUpInside)
        addSubview(reviewBtn)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(group: DuplicateGroup, index: Int, onReview: (() -> Void)?) {
        self.onReview = onReview
        let pct = max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
        label.text = "Group \(index + 1)  ·  \(pct)% similarity"
        label.sizeToFit()
        setNeedsLayout()
    }

    @objc private func reviewTapped() { onReview?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let pillH: CGFloat = 20
        let hPad: CGFloat = 8
        let pillW = label.intrinsicContentSize.width + hPad * 2
        pill.frame = CGRect(x: 12, y: (h - pillH) / 2, width: pillW, height: pillH)
        label.frame = CGRect(x: hPad, y: (pillH - label.intrinsicContentSize.height) / 2,
                             width: label.intrinsicContentSize.width, height: label.intrinsicContentSize.height)
        let btnW: CGFloat = 60, btnH: CGFloat = 22
        reviewBtn.frame = CGRect(x: pill.frame.maxX + 8, y: (h - btnH) / 2, width: btnW, height: btnH)
    }
}

// MARK: - Section Header (Date Groups)

final class UIDateSectionHeader: UICollectionReusableView {
    static let identifier = "UIDateSectionHeader"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabel
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.text = title
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 8, y: 0, width: bounds.width - 16, height: bounds.height)
    }
}

// MARK: - SwiftUI Wrapper

struct UICollectionThumbGridView: UIViewRepresentable {
    let photos: [PhotoItem]
    let itemSize: CGFloat
    let cellHeight: CGFloat
    let selectedPhotos: Set<UUID>
    let callbacks: ThumbCellCallbacks
    var duplicateResult: DuplicateScanResult? = nil
    var onReview: ((DuplicateGroup, Int) -> Void)? = nil
    var dateGroups: [(title: String, photos: [PhotoItem])] = []
    var sortOption: ThumbGridViewModel.SortOption = .name
    @Binding var scrollToPhotoId: UUID?

    private var isDateGrouped: Bool { sortOption == .dateCreated && !dateGroups.isEmpty }

    func makeCoordinator() -> Coordinator {
        Coordinator(itemSize: itemSize, cellHeight: cellHeight, callbacks: callbacks)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        context.coordinator.scrollView = scrollView
        buildCollectionView(in: scrollView, context: context)
        return scrollView
    }

    private func buildCollectionView(in scrollView: UIScrollView, context: Context) {
        // Remove any existing collection view
        scrollView.subviews.forEach { $0.removeFromSuperview() }

        let c = context.coordinator
        let hasHeaders = duplicateResult != nil || isDateGrouped
        let layout = makeLayout(hasHeaders: hasHeaders)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.allowsSelection = true
        cv.allowsMultipleSelection = true
        cv.dataSource = c
        cv.delegate = c
        cv.register(UIThumbCollectionCell.self, forCellWithReuseIdentifier: UIThumbCollectionCell.identifier)
        cv.register(UIDuplicateSectionHeader.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: UIDuplicateSectionHeader.identifier)
        cv.register(UIDateSectionHeader.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: UIDateSectionHeader.identifier)
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        c.collectionView = cv
        scrollView.addSubview(cv)
        cv.frame = scrollView.bounds
    }

    private func makeLayout(hasHeaders: Bool) -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: itemSize, height: cellHeight)
        layout.minimumInteritemSpacing = 3
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 6, left: 3, bottom: 6, right: 3)
        if hasHeaders {
            layout.headerReferenceSize = CGSize(width: 0, height: 32)
        }
        return layout
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let c = context.coordinator

        let isDupNow  = duplicateResult != nil
        let wasDup    = c.duplicateResult != nil
        let isDateNow = isDateGrouped
        let wasDate   = c.sortOption == .dateCreated && !c.dateGroups.isEmpty
        let modeChanged = isDupNow != wasDup || isDateNow != wasDate

        let photosChanged     = c.photos.map(\.id) != photos.map(\.id)
        let sizeChanged       = c.itemSize != itemSize || c.cellHeight != cellHeight
        let selectionChanged  = c.selectedPhotos != selectedPhotos
        let dupChanged        = c.duplicateResult?.groups.map(\.id) != duplicateResult?.groups.map(\.id)
        let dateGroupsChanged = c.dateGroups.map({ $0.title }) != dateGroups.map({ $0.title })

        let latestMap  = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let oldPhotoMap = Dictionary(uniqueKeysWithValues: c.photos.map { ($0.id, $0) })

        // Update coordinator state first
        c.photos = photos
        c.itemSize = itemSize
        c.cellHeight = cellHeight
        c.selectedPhotos = selectedPhotos
        c.callbacks = callbacks
        c.duplicateResult = duplicateResult
        c.onReview = onReview
        c.dateGroups = dateGroups
        c.sortOption = sortOption
        c.photosById = Dictionary(uniqueKeysWithValues: photos.map { ($0.path, $0) })

        if modeChanged {
            buildCollectionView(in: scrollView, context: context)
            return
        }

        let cv = c.collectionView

        if photosChanged || sizeChanged || dupChanged || dateGroupsChanged {
            if sizeChanged, let layout = cv?.collectionViewLayout as? UICollectionViewFlowLayout {
                layout.itemSize = CGSize(width: itemSize, height: cellHeight)
                let hasHeaders = duplicateResult != nil || isDateGrouped
                layout.headerReferenceSize = hasHeaders ? CGSize(width: 0, height: 32) : .zero
            }
            cv?.reloadData()
        } else {
            cv?.indexPathsForVisibleItems.forEach { ip in
                guard let cell = cv?.cellForItem(at: ip) as? UIThumbCollectionCell,
                      let path = cell.currentPath,
                      let photo = latestMap.values.first(where: { $0.path == path }) else { return }
                let isSelected = selectedPhotos.contains(photo.id)
                if oldPhotoMap[photo.id] != photo {
                    cell.configure(with: photo, isSelected: isSelected, itemSize: itemSize, callbacks: callbacks)
                } else if selectionChanged {
                    cell.updateSelection(isSelected: isSelected)
                }
            }
        }

        // Scroll to photo
        if let photoId = scrollToPhotoId {
            var targetIndexPath: IndexPath?
            if let result = duplicateResult {
                outer: for (s, group) in result.groups.enumerated() {
                    for (i, photo) in group.photos.enumerated() {
                        if photo.id == photoId {
                            targetIndexPath = IndexPath(item: i, section: s)
                            break outer
                        }
                    }
                }
            } else if isDateGrouped {
                outer: for (s, group) in dateGroups.enumerated() {
                    for (i, photo) in group.photos.enumerated() {
                        if photo.id == photoId {
                            targetIndexPath = IndexPath(item: i, section: s)
                            break outer
                        }
                    }
                }
            } else if let index = photos.firstIndex(where: { $0.id == photoId }) {
                targetIndexPath = IndexPath(item: index, section: 0)
            }
            if let ip = targetIndexPath {
                cv?.scrollToItem(at: ip, at: .centeredVertically, animated: true)
            }
            DispatchQueue.main.async { self.scrollToPhotoId = nil }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var photos: [PhotoItem] = []
        var itemSize: CGFloat
        var cellHeight: CGFloat
        var selectedPhotos: Set<UUID> = []
        var callbacks: ThumbCellCallbacks
        var duplicateResult: DuplicateScanResult? = nil
        var onReview: ((DuplicateGroup, Int) -> Void)?
        var photosById: [String: PhotoItem] = [:]
        var dateGroups: [(title: String, photos: [PhotoItem])] = []
        var sortOption: ThumbGridViewModel.SortOption = .name
        weak var collectionView: UICollectionView?
        weak var scrollView: UIScrollView?

        private var isDateGrouped: Bool { sortOption == .dateCreated && !dateGroups.isEmpty }

        init(itemSize: CGFloat, cellHeight: CGFloat, callbacks: ThumbCellCallbacks) {
            self.itemSize = itemSize
            self.cellHeight = cellHeight
            self.callbacks = callbacks
        }

        private func photosForSection(_ section: Int) -> [PhotoItem] {
            if let result = duplicateResult {
                guard section < result.groups.count else { return [] }
                return result.groups[section].photos.map { photosById[$0.path] ?? $0 }
            }
            if isDateGrouped {
                guard section < dateGroups.count else { return [] }
                return dateGroups[section].photos
            }
            return section == 0 ? photos : []
        }

        // MARK: UICollectionViewDataSource

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            if duplicateResult != nil { return duplicateResult!.groups.count }
            if isDateGrouped { return dateGroups.count }
            return 1
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            photosForSection(section).count
        }

        func collectionView(_ collectionView: UICollectionView,
                            cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: UIThumbCollectionCell.identifier,
                for: indexPath) as! UIThumbCollectionCell
            let photo = photosForSection(indexPath.section)[indexPath.item]
            cell.configure(with: photo,
                           isSelected: selectedPhotos.contains(photo.id),
                           itemSize: itemSize,
                           callbacks: callbacks)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView,
                            viewForSupplementaryElementOfKind kind: String,
                            at indexPath: IndexPath) -> UICollectionReusableView {
            guard kind == UICollectionView.elementKindSectionHeader else {
                return UICollectionReusableView()
            }
            // Duplicate header
            if let result = duplicateResult, indexPath.section < result.groups.count {
                let header = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: UIDuplicateSectionHeader.identifier,
                    for: indexPath) as! UIDuplicateSectionHeader
                let group = result.groups[indexPath.section]
                let idx = indexPath.section
                header.configure(group: group, index: idx, onReview: { [weak self] in
                    self?.onReview?(group, idx)
                })
                return header
            }
            // Date header
            if isDateGrouped, indexPath.section < dateGroups.count {
                let header = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: UIDateSectionHeader.identifier,
                    for: indexPath) as! UIDateSectionHeader
                header.configure(title: dateGroups[indexPath.section].title)
                return header
            }
            return UICollectionReusableView()
        }

        // MARK: UICollectionViewDelegate

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            let photo = photosForSection(indexPath.section)[indexPath.item]
            callbacks.onTap(photo, .none)
        }

        func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
            let photo = photosForSection(indexPath.section)[indexPath.item]
            callbacks.onTap(photo, .none)
        }
    }
}
#endif
