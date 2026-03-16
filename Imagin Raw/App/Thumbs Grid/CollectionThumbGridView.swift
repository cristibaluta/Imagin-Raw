//
//  CollectionThumbGridView.swift
//  Imagin Raw
//
//  NSCollectionView-based photo grid for comparison with SwiftUI LazyVGrid.
//  Displays only thumbnails — no labels, no ratings overlay.
//

import SwiftUI
import AppKit

// MARK: - SwiftUI Wrapper

struct CollectionThumbGridView: NSViewRepresentable {
    let photos: [PhotoItem]
    let itemSize: CGFloat
    var onSelect: ((PhotoItem) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(itemSize: itemSize, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.backgroundColor = NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = context.coordinator.makeLayout(itemSize: itemSize)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)]
        collectionView.register(ThumbCollectionItem.self,
                                forItemWithIdentifier: ThumbCollectionItem.identifier)

        context.coordinator.collectionView = collectionView
        scrollView.documentView = collectionView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let collectionView = coordinator.collectionView

        let photosChanged = coordinator.photos.map(\.id) != photos.map(\.id)
        let sizeChanged = coordinator.itemSize != itemSize

        coordinator.photos = photos
        coordinator.itemSize = itemSize
        coordinator.onSelect = onSelect

        if sizeChanged {
            collectionView?.collectionViewLayout = coordinator.makeLayout(itemSize: itemSize)
        }

        if photosChanged || sizeChanged {
            collectionView?.reloadData()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var photos: [PhotoItem] = []
        var itemSize: CGFloat
        var onSelect: ((PhotoItem) -> Void)?
        weak var collectionView: NSCollectionView?

        init(itemSize: CGFloat, onSelect: ((PhotoItem) -> Void)?) {
            self.itemSize = itemSize
            self.onSelect = onSelect
        }

        func makeLayout(itemSize: CGFloat) -> NSCollectionViewFlowLayout {
            let layout = NSCollectionViewFlowLayout()
            layout.itemSize = NSSize(width: itemSize, height: itemSize)
            layout.minimumInteritemSpacing = 0
            layout.minimumLineSpacing = 8
            layout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
            return layout
        }

        // MARK: NSCollectionViewDataSource

        func collectionView(_ collectionView: NSCollectionView,
                            numberOfItemsInSection section: Int) -> Int {
            photos.count
        }

        func collectionView(_ collectionView: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: ThumbCollectionItem.identifier,
                                               for: indexPath) as! ThumbCollectionItem
            item.configure(with: photos[indexPath.item])
            return item
        }

        // MARK: NSCollectionViewDelegate

        func collectionView(_ collectionView: NSCollectionView,
                            didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let index = indexPaths.first?.item, index < photos.count else { return }
            onSelect?(photos[index])
        }
    }
}

// MARK: - NSCollectionViewItem

final class ThumbCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbCollectionItem")

    private let imageView2 = NSImageView()
    private var currentPath: String?
    private var loadTask: DispatchWorkItem?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 41/255, green: 41/255, blue: 41/255, alpha: 1).cgColor
        container.layer?.cornerRadius = 2

        imageView2.imageScaling = .scaleProportionallyUpOrDown
        imageView2.imageAlignment = .alignCenter
        imageView2.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView2)
        NSLayoutConstraint.activate([
            imageView2.topAnchor.constraint(equalTo: container.topAnchor),
            imageView2.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView2.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView2.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        self.view = container
    }

    func configure(with photo: PhotoItem) {
        // Cancel any in-flight load for a previous photo
        loadTask?.cancel()
        loadTask = nil

        // If same photo, nothing to do
        if currentPath == photo.path { return }
        currentPath = photo.path
        imageView2.image = nil

        // Check memory cache first (instant, no work item needed)
        if let cached = ThumbsManager.shared.getCachedThumbnail(for: photo.path) {
            imageView2.image = cached
            return
        }

        // Async load via ThumbsManager
        let path = photo.path
        let work = DispatchWorkItem { [weak self] in
            ThumbsManager.shared.loadThumbnail(for: path, priority: .medium) { image in
                DispatchQueue.main.async {
                    guard self?.currentPath == path else { return }
                    self?.imageView2.image = image
                }
            }
        }
        loadTask = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentPath = nil
        imageView2.image = nil
    }
}
