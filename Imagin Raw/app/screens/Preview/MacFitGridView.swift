//
//  MacFitGridView.swift
//  Imagin Raw
//
//  Reusable NSCollectionView that shows N images, each as a bare image.
//  Tries to fit all of them on screen (ReviewFitLayout); when they would become
//  too small it falls back to a regular scrolling grid.
//
#if os(macOS)
import SwiftUI
import AppKit

// MARK: - SwiftUI wrapper

struct MacFitGridView: NSViewRepresentable {
    let photos: [PhotoItem]
    let cacheManager: PhotoCacheManager
    var spacing: CGFloat = 12
    var padding: CGFloat = 12

    func makeCoordinator() -> MacFitGridCoordinator {
        MacFitGridCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coord = context.coordinator

        let layout = MacFitGridLayout()
        layout.spacing = spacing
        layout.padding = padding
        layout.aspects = photos.map(\.fitAspectRatio)

        let cv = NSCollectionView()
        cv.collectionViewLayout = layout
        cv.dataSource = coord
        cv.isSelectable = false
        cv.backgroundColors = [.clear]
        cv.register(MacFitImageCell.self, forItemWithIdentifier: MacFitImageCell.identifier)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = cv

        coord.photos = photos
        coord.cacheManager = cacheManager
        coord.collectionView = cv
        coord.layout = layout
        coord.observe(scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.cacheManager = cacheManager

        guard let cv = coord.collectionView, let layout = coord.layout else {
            return
        }
        let idsChanged = coord.photos.map(\.id) != photos.map(\.id)
        let metricsChanged = layout.spacing != spacing || layout.padding != padding

        coord.photos = photos
        layout.spacing = spacing
        layout.padding = padding

        if idsChanged {
            layout.aspects = photos.map(\.fitAspectRatio)
            cv.reloadData()
            cv.scroll(.zero)
        } else if metricsChanged {
            layout.invalidateLayout()
        }
    }
}

// MARK: - Coordinator

@MainActor
final class MacFitGridCoordinator: NSObject, NSCollectionViewDataSource {
    var photos: [PhotoItem] = []
    var cacheManager: PhotoCacheManager?
    weak var collectionView: NSCollectionView?
    weak var layout: MacFitGridLayout?
    // Accessed from the nonisolated deinit only to remove the observer
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// Re-layout whenever the visible area changes (window resize, split view drag...).
    func observe(_ scrollView: NSScrollView) {
        scrollView.contentView.postsFrameChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                          object: scrollView.contentView,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.layout?.invalidateLayout()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        photos.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: MacFitImageCell.identifier, for: indexPath)
        if let cell = item as? MacFitImageCell, let cacheManager, indexPath.item < photos.count {
            cell.configure(with: photos[indexPath.item], cacheManager: cacheManager)
        }
        return item
    }
}

// MARK: - Layout

final class MacFitGridLayout: NSCollectionViewLayout {
    var aspects: [CGFloat] = [] {
        didSet { invalidateLayout() }
    }
    var spacing: CGFloat = 12
    var padding: CGFloat = 12
    /// Minimum cell width used by the scrolling fallback to decide the column count.
    var minColumnWidth: CGFloat = 320

    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var contentSize: NSSize = .zero

    override var collectionViewContentSize: NSSize {
        contentSize
    }

    override func prepare() {
        super.prepare()
        attributes = []
        guard let cv = collectionView else {
            contentSize = .zero
            return
        }
        let visible = cv.enclosingScrollView?.contentSize ?? cv.bounds.size
        guard visible.width > 0, visible.height > 0, !aspects.isEmpty else {
            contentSize = visible
            return
        }
        let available = NSSize(width: visible.width - padding * 2, height: visible.height - padding * 2)

        if let fitted = ReviewFitLayout.best(aspects: aspects, in: available, spacing: spacing) {
            layoutFitted(fitted, visible: visible, available: available)
        } else {
            layoutScrolling(visible: visible, available: available)
        }
    }

    /// Everything fits: rows centered in the visible area, no scrolling.
    private func layoutFitted(_ fitted: ReviewFitLayout, visible: NSSize, available: NSSize) {
        let totalH = fitted.rows.reduce(CGFloat(0)) { $0 + ($1.first?.size.height ?? 0) }
            + spacing * CGFloat(max(0, fitted.rows.count - 1))
        var y = padding + max(0, (available.height - totalH) / 2)

        for row in fitted.rows {
            let rowW = row.reduce(CGFloat(0)) { $0 + $1.size.width } + spacing * CGFloat(max(0, row.count - 1))
            var x = padding + max(0, (available.width - rowW) / 2)
            for item in row {
                add(item.index, frame: NSRect(x: x, y: y, width: item.size.width, height: item.size.height))
                x += item.size.width + spacing
            }
            y += (row.first?.size.height ?? 0) + spacing
        }
        contentSize = visible
    }

    /// Too many photos: uniform cells in fixed columns, vertical scroll.
    private func layoutScrolling(visible: NSSize, available: NSSize) {
        let cols = max(1, Int((available.width + spacing) / (minColumnWidth + spacing)))
        let cellW = (available.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH = cellW / 1.5

        for i in 0..<aspects.count {
            let row = i / cols
            let col = i % cols
            add(i, frame: NSRect(x: padding + CGFloat(col) * (cellW + spacing),
                                 y: padding + CGFloat(row) * (cellH + spacing),
                                 width: cellW,
                                 height: cellH))
        }
        let rows = (aspects.count + cols - 1) / cols
        let totalH = padding * 2 + CGFloat(rows) * cellH + CGFloat(max(0, rows - 1)) * spacing
        contentSize = NSSize(width: visible.width, height: max(totalH, visible.height))
    }

    private func add(_ index: Int, frame: NSRect) {
        let attrs = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        attrs.frame = frame
        attributes.append(attrs)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        attributes.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.size != contentSize
    }
}

// MARK: - Cell

final class MacFitImageCell: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("MacFitImageCell")

    private let imageContainer = NSImageView()
    private var loadTask: Task<Void, Never>?
    private var currentPhotoId: UUID?

    override func loadView() {
        imageContainer.imageScaling = .scaleProportionallyUpOrDown
        imageContainer.imageAlignment = .alignCenter
        if #available(macOS 14.0, *) {
            imageContainer.preferredImageDynamicRange = .high
        }
        view = imageContainer
    }

    func configure(with photo: PhotoItem, cacheManager: PhotoCacheManager) {
        guard currentPhotoId != photo.id else {
            return
        }
        loadTask?.cancel()
        currentPhotoId = photo.id
        imageContainer.image = nil

        loadTask = Task { [weak self] in
            let image = await cacheManager.getImage(for: photo)
            guard !Task.isCancelled, let self, self.currentPhotoId == photo.id else {
                return
            }
            self.imageContainer.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentPhotoId = nil
        imageContainer.image = nil
    }
}
#endif
