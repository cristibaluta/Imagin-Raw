//
//  PDFEditorViewModel.swift
//  Imagin Raw
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class PDFEditorViewModel: ObservableObject {

    // MARK: - Published state
    @Published private(set) var images: [IRImage] = []
    @Published private(set) var isLoadingImages = false
    @Published var columns: Int = 3
    @Published var showFileName: Bool = true
    @Published private(set) var pdfDocument: PDFDocument? = nil
    @Published private(set) var isExporting = false
    @Published var exportError: String? = nil
    @Published var showExportPanel = false
    @Published private(set) var exportedFileDocument: PDFFileDocument? = nil

    // MARK: - Layout constants
    private let pageWidth:  CGFloat = 595   // A4 points
    private let pageHeight: CGFloat = 842
    private let margin:     CGFloat = 36
    private let spacing:    CGFloat = 24
    private let titleHeight: CGFloat = 48
    private let labelHeight: CGFloat = 18

    let photos: [PhotoItem]
    let albumName: String
    private let cacheManager: PhotoCacheManager

    init(photos: [PhotoItem], albumName: String, cacheManager: PhotoCacheManager) {
        self.photos = photos
        self.albumName = albumName
        self.cacheManager = cacheManager
    }

    // MARK: - Image loading

    func loadImages() {
        guard images.isEmpty else { return }
        isLoadingImages = true
        Task {
            var loaded: [IRImage] = []
            for photo in photos {
                if let img = await cacheManager.getImage(for: photo) {
                    loaded.append(img)
                }
            }
            self.images = loaded
            self.isLoadingImages = false
            self.rebuildPDF()
        }
    }

    // MARK: - PDF generation

    func rebuildPDF() {
        guard !images.isEmpty else { return }
        pdfDocument = buildPDF()
    }

    private func buildPDF() -> PDFDocument {
        let doc = PDFDocument()
        let cols = max(1, columns)

        let availableWidth  = pageWidth  - margin * 2 - spacing * CGFloat(cols - 1)
        let cellWidth       = availableWidth / CGFloat(cols)
        let cellImageHeight = cellWidth * 0.75   // 4:3 aspect in each cell
        let rowHeight       = cellImageHeight + (showFileName ? labelHeight + 4 : 0) + spacing

        var imageIndex = 0
        var pageIndex  = 0

        while imageIndex < images.count {
            // Calculate rows for this page
            let usedTop     = margin + (pageIndex == 0 ? titleHeight + spacing : 0)
            let availHeight = pageHeight - usedTop - margin
            let rowsPerPage = max(1, Int(availHeight / rowHeight))
            let cellsOnPage = rowsPerPage * cols

            // Render the page
            let renderer = PDFPageRenderer(
                images:        Array(images[imageIndex ..< min(imageIndex + cellsOnPage, images.count)]),
                photoNames:    photos[imageIndex ..< min(imageIndex + cellsOnPage, photos.count)].map {
                                   URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent
                               },
                pageSize:      CGSize(width: pageWidth, height: pageHeight),
                margin:        margin,
                spacing:       spacing,
                cols:          cols,
                cellWidth:     cellWidth,
                cellImageHeight: cellImageHeight,
                labelHeight:   labelHeight,
                showFileName:  showFileName,
                title:         pageIndex == 0 ? albumName : nil,
                titleHeight:   titleHeight
            )
            let page = PDFPageFromRenderer(renderer: renderer)
            doc.insert(page, at: doc.pageCount)

            imageIndex += cellsOnPage
            pageIndex  += 1
        }
        return doc
    }

    // MARK: - Export

    func exportPDF() {
        guard let doc = pdfDocument else { return }
        isExporting = true
        exportError = nil
        Task {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(albumName).pdf")
            doc.write(to: tmp)
            self.exportedFileDocument = PDFFileDocument(url: tmp)
            self.showExportPanel = true
            self.isExporting = false
        }
    }
}

// MARK: - Helpers

/// Wraps a rendered PDF page using Core Graphics.
private final class PDFPageFromRenderer: PDFPage {
    private let renderer: PDFPageRenderer
    var bounds: CGRect {
        get { CGRect(origin: .zero, size: renderer.pageSize) }
        set { }
    }
    init(renderer: PDFPageRenderer) {
        self.renderer = renderer
        super.init()
    }
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        renderer.draw(in: context)
    }
}

private struct PDFPageRenderer {
    let images:         [IRImage]
    let photoNames:     [String]
    let pageSize:       CGSize
    let margin:         CGFloat
    let spacing:        CGFloat
    let cols:           Int
    let cellWidth:      CGFloat
    let cellImageHeight: CGFloat
    let labelHeight:    CGFloat
    let showFileName:   Bool
    let title:          String?
    let titleHeight:    CGFloat

    func draw(in ctx: CGContext) {
        let w = pageSize.width
        let h = pageSize.height

        // PDF coordinates: origin bottom-left, Y grows up.
        // We work in "top-left" space (y grows DOWN from 0) and convert at draw time.
        // Helper: convert top-left Y → PDF Y (flip)
        func pdfY(_ topY: CGFloat) -> CGFloat { h - topY }

        // Background
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        var topY: CGFloat = margin + titleHeight  // leave full titleHeight above the baseline

        // ── Title ───────────────────────────────────────────────────────────
        if let title {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: title, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            // Baseline at the current topY position (already offset by titleHeight)
            let baseline = pdfY(topY)
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: margin, y: baseline)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
            topY += spacing  // images start just below the title baseline
        }

        let rowHeight = cellImageHeight + (showFileName ? labelHeight + 4 : 0) + spacing

        for (i, img) in images.enumerated() {
            let col = i % cols
            let row = i / cols

            let x    = margin + CGFloat(col) * (cellWidth + spacing)
            let cellTopY = topY + CGFloat(row) * rowHeight   // top-left space

            // ── Image ───────────────────────────────────────────────────────
            // CGContext.draw(cgImage:in:) uses PDF coordinates (origin bottom-left)
            let cellPDFRect = CGRect(x: x,
                                     y: pdfY(cellTopY + cellImageHeight),
                                     width: cellWidth,
                                     height: cellImageHeight)

            // Grey placeholder
            ctx.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
            ctx.fill(cellPDFRect)

            if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let imgW  = CGFloat(cgImg.width)
                let imgH  = CGFloat(cgImg.height)
                let scale = min(cellWidth / imgW, cellImageHeight / imgH)
                let dw    = imgW * scale
                let dh    = imgH * scale
                let dx    = cellPDFRect.minX + (cellWidth  - dw) / 2
                let dy    = cellPDFRect.minY + (cellImageHeight - dh) / 2
                ctx.draw(cgImg, in: CGRect(x: dx, y: dy, width: dw, height: dh))
            }

            // ── File name label ─────────────────────────────────────────────
            if showFileName, i < photoNames.count {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: NSColor.darkGray
                ]
                let str  = NSAttributedString(string: photoNames[i], attributes: attrs)
                let line = CTLineCreateWithAttributedString(str)
                let lineWidth = CTLineGetImageBounds(line, ctx).width
                let lx = x + (cellWidth - lineWidth) / 2
                // Baseline just below the image in top-left space
                let labelTopY  = cellTopY + cellImageHeight + 3
                let labelBaseline = pdfY(labelTopY + labelHeight - 3)
                ctx.saveGState()
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: lx, y: labelBaseline)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            }
        }
    }
}

// MARK: - FileDocument wrapper for fileExporter

struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnknown)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Data(contentsOf: url)
        return FileWrapper(regularFileWithContents: data)
    }
}
