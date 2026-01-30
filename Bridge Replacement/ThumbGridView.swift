import SwiftUI

struct ThumbGridView: View {
    let photos: [PhotoItem]
    @ObservedObject var model: BrowserModel
    @FocusState private var isFocused: Bool
    @State private var lastScrolledRow: Int = -1

    let columns = [
        GridItem(.fixed(108), spacing: 8),
        GridItem(.fixed(108), spacing: 8),
        GridItem(.fixed(108), spacing: 8)
    ]
    private let columnsCount = 3

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(photos, id: \.id) { photo in
                            ThumbCell(photo: photo, isSelected: model.selectedPhoto?.id == photo.id)
                                .frame(width: 100, height: 150)
                                .id(photo.id)
                                .onTapGesture {
                                    model.selectedPhoto = photo
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .scrollContentBackground(.hidden)
                .frame(width: 380) // Fixed width for better performance
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onKeyPress { keyPress in
                    handleKeyPress(keyPress, proxy: proxy, viewportHeight: geometry.size.height)
                }
                .onAppear {
                    isFocused = true
                    if model.selectedPhoto == nil && !photos.isEmpty {
                        model.selectedPhoto = photos.first
                    }
                }
                .onChange(of: photos) { _, newPhotos in
                    if !newPhotos.isEmpty {
                        model.selectedPhoto = newPhotos.first
                    }
                }
            }
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress, proxy: ScrollViewProxy, viewportHeight: CGFloat) -> KeyPress.Result {
        guard !photos.isEmpty else { return .ignored }

        let currentIndex = photos.firstIndex { $0.id == model.selectedPhoto?.id } ?? 0
        var newIndex = currentIndex

        switch keyPress.key {
        case .leftArrow:
            newIndex = max(0, currentIndex - 1)
        case .rightArrow:
            newIndex = min(photos.count - 1, currentIndex + 1)
        case .upArrow:
            newIndex = max(0, currentIndex - columnsCount)
        case .downArrow:
            newIndex = min(photos.count - 1, currentIndex + columnsCount)
        default:
            return .ignored
        }

        if newIndex != currentIndex {
            model.selectedPhoto = photos[newIndex]

            // Auto-scroll only when moving vertically and reaching visible edges
            if keyPress.key == .upArrow || keyPress.key == .downArrow {
                let currentRow = currentIndex / columnsCount
                let newRow = newIndex / columnsCount
                let totalRows = (photos.count + columnsCount - 1) / columnsCount

                if newRow != currentRow && newRow != lastScrolledRow {
                    let thumbnailHeight: CGFloat = 150 + 8
                    let visibleRows = Int(viewportHeight / thumbnailHeight)

                    // Only scroll when we have enough content to warrant scrolling
                    guard totalRows > visibleRows else { return .handled }

                    // Calculate approximate visible range (this is simplified but effective)
                    let middleRow = totalRows / 2
                    let scrollTriggerDistance = visibleRows / 3 // Trigger when 1/3 from edge

                    // Check if we're approaching edges of the entire dataset
                    // This will effectively scroll when reaching visible viewport edges
                    let isApproachingTop = newRow < scrollTriggerDistance
                    let isApproachingBottom = newRow > (totalRows - scrollTriggerDistance)

                    // Also scroll periodically to keep selection visible in large datasets
                    let shouldPeriodicScroll = abs(newRow - middleRow) % (visibleRows - 1) == 0

                    if isApproachingTop || isApproachingBottom || (shouldPeriodicScroll && totalRows > visibleRows * 2) {
                        lastScrolledRow = newRow
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(photos[newIndex].id, anchor: UnitPoint.center)
                        }
                    }
                }
            }

            return .handled
        }

        return .ignored
    }
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}
