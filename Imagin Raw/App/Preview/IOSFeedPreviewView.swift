//
//  IOSFeedPreviewView.swift
//  Imagin Raw
//
//  Instagram-style vertical feed for iOS.
//  One full-width cell per photo: image fills screen width, EXIF below.
//  Opens at the tapped photo and lets the user scroll through the whole album.
//

#if os(iOS)
import SwiftUI
import UIKit

struct IOSFeedPreviewView: UIViewRepresentable {

    /// All photos in the current folder/album.
    let photos: [PhotoItem]
    /// The photo that was tapped — we scroll to it on first appear.
    let initialPhoto: PhotoItem

    func makeCoordinator() -> Coordinator {
        Coordinator(photos: photos, initialPhoto: initialPhoto)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .black
        cv.isPagingEnabled = false
        cv.showsVerticalScrollIndicator = true
        cv.isPrefetchingEnabled = true
        cv.register(IOSFeedCell.self, forCellWithReuseIdentifier: IOSFeedCell.identifier)

        let c = context.coordinator
        cv.dataSource = c
        cv.delegate   = c
        cv.prefetchDataSource = c
        c.collectionView = cv

        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let c = context.coordinator
        let photosChanged = c.photos.map(\.id) != photos.map(\.id)
        c.photos = photos
        c.initialPhoto = initialPhoto

        if photosChanged {
            cv.reloadData()
        }
        // Scroll to initial photo once the layout is ready
        c.scrollToInitialPhotoIfNeeded()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
                        UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {

        var photos: [PhotoItem]
        var initialPhoto: PhotoItem
        weak var collectionView: UICollectionView?
        private var hasScrolledToInitial = false

        init(photos: [PhotoItem], initialPhoto: PhotoItem) {
            self.photos = photos
            self.initialPhoto = initialPhoto
        }

        // MARK: Scroll to initial

        func scrollToInitialPhotoIfNeeded() {
            guard !hasScrolledToInitial,
                  let cv = collectionView,
                  let idx = photos.firstIndex(where: { $0.id == initialPhoto.id }) else { return }
            // Wait one run-loop so the collection view has measured its cells
            DispatchQueue.main.async { [weak self, weak cv] in
                guard let self, let cv else { return }
                let ip = IndexPath(item: idx, section: 0)
                cv.scrollToItem(at: ip, at: .top, animated: false)
                self.hasScrolledToInitial = true
            }
        }

        // MARK: UICollectionViewDataSource

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            photos.count
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: IOSFeedCell.identifier,
                                              for: indexPath) as! IOSFeedCell
            cell.configure(with: photos[indexPath.item])
            return cell
        }

        // MARK: UICollectionViewDelegateFlowLayout

        func collectionView(_ cv: UICollectionView,
                            layout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let w = cv.bounds.width
            return CGSize(width: w, height: IOSFeedCell.cellHeight(for: w))
        }

        // MARK: UICollectionViewDataSourcePrefetching

        func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            for ip in indexPaths {
                let photo = photos[ip.item]
                PreviewsManager.shared.loadPreview(for: photo) { _, _ in }
            }
        }

        func collectionView(_ cv: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            for ip in indexPaths {
                PreviewsManager.shared.cancelPreview(for: photos[ip.item].path)
            }
        }
    }
}
#endif
