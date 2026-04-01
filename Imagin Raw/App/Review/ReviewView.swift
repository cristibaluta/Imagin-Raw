//
//  ReviewView.swift
//  Imagin Raw
//
//  Full-screen review view for a single duplicate group.
//  Shows all photos side-by-side with name, rating, approve and delete actions.
//

import SwiftUI

struct ReviewView: View {
    let group: DuplicateGroup
    let groupIndex: Int
    let onRatingChanged: (PhotoItem, Int) -> Void
    let onApprove: (PhotoItem) -> Void
    let onMarkForDeletion: (PhotoItem) -> Void
    let onDismiss: () -> Void

    // Live photo state — updated when actions are taken
    @State private var photos: [PhotoItem]

    init(group: DuplicateGroup,
         groupIndex: Int,
         onRatingChanged: @escaping (PhotoItem, Int) -> Void,
         onApprove: @escaping (PhotoItem) -> Void,
         onMarkForDeletion: @escaping (PhotoItem) -> Void,
         onDismiss: @escaping () -> Void) {
        self.group = group
        self.groupIndex = groupIndex
        self.onRatingChanged = onRatingChanged
        self.onApprove = onApprove
        self.onMarkForDeletion = onMarkForDeletion
        self.onDismiss = onDismiss
        _photos = State(initialValue: group.photos)
    }

    private var similarity: Int {
        max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
    }

    private var isPortrait: Bool {
        guard let first = photos.first,
              let w = first.width,
              let h = first.height else {
            return true
        }
        return h > w
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                let hPad: CGFloat = 20
                let spacing: CGFloat = 16
                let cardW = (geo.size.width - hPad * 3 - spacing) / (isPortrait ? 3 : 2)
                let columns = isPortrait
                ? [
                    GridItem(.fixed(cardW), spacing: spacing),
                    GridItem(.fixed(cardW), spacing: spacing),
                    GridItem(.fixed(cardW), spacing: spacing)
                ]
                : [
                    GridItem(.fixed(cardW), spacing: spacing),
                    GridItem(.fixed(cardW), spacing: spacing)
                ]
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(photos) { photo in
                            ReviewPhotoCard(
                                photo: photo,
                                onRatingChanged: { rating in onRatingChanged(photo, rating); bump() },
                                onApprove: { onApprove(photo); bump() },
                                onMarkForDeletion: { onMarkForDeletion(photo); bump() }
                            )
                        }
                    }
                    .padding(hPad)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.underPageBackgroundColor))
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func bump() {
        let copy = photos; photos = copy
    }
}
