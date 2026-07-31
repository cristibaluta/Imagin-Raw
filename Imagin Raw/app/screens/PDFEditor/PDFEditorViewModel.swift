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
    @Published var showNumbers: Bool = true
    @Published var showFileName: Bool = true
    @Published var showCheckbox: Bool = true
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
        guard images.isEmpty else {
            return
        }
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
        guard !images.isEmpty else {
            return
        }
        pdfDocument = buildPDF()
    }

    private func buildPDF() -> PDFDocument {
        let doc = PDFDocument()
        let cols = max(1, columns)

        let availableWidth  = pageWidth  - margin * 2 - spacing * CGFloat(cols - 1)
        let cellWidth       = availableWidth / CGFloat(cols)
        let cellHeight      = cellWidth
        let checkboxSize:   CGFloat = 12
        // Label row is shared by text + checkbox — only one row below the image
        let labelRowHeight: CGFloat = (showNumbers || showFileName || showCheckbox) ? labelHeight + 8 : 0
        let rowHeight = cellHeight + labelRowHeight + spacing

        var imageIndex = 0
        var pageIndex  = 0

        while imageIndex < images.count {
            // startTopY is where the first row of images begins (top-left space)
            let startTopY: CGFloat = margin*2 + (pageIndex == 0 ? titleHeight + spacing : margin)
            let availHeight = pageHeight - startTopY - margin
            let rowsPerPage = max(1, Int(availHeight / rowHeight))
            let cellsOnPage = rowsPerPage * cols

            let cellRange  = imageIndex ..< min(imageIndex + cellsOnPage, images.count)
            let photoRange = imageIndex ..< min(imageIndex + cellsOnPage, photos.count)

            let renderer = PDFPageRenderer(
                images:          Array(images[cellRange]),
                photoNames:      photos[photoRange].map {
                                     URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent
                                 },
                photoIDs:        photos[photoRange].map { $0.url.deletingPathExtension().lastPathComponent },
                pageSize:        CGSize(width: pageWidth, height: pageHeight),
                pageNr:          pageIndex + 1,
                margin:          margin,
                spacing:         spacing,
                startingIndex:   imageIndex,
                cols:            cols,
                cellWidth:       cellWidth,
                cellHeight:      cellHeight,
                labelHeight:     labelHeight,
                checkboxSize:    checkboxSize,
                showNumbers:     showNumbers,
                showFileName:    showFileName,
                showCheckbox:    showCheckbox,
                title:           pageIndex == 0 ? albumName : nil,
                titleHeight:     titleHeight,
                startTopY:       startTopY          // ← single source of truth
            )
            let page = PDFPageFromRenderer(renderer: renderer)

            // Add interactive checkbox annotations aligned with startTopY
            if showCheckbox {
                for (i, photoID) in renderer.photoIDs.enumerated() {
                    let col          = i % cols
                    let row          = i / cols
                    let x            = margin + CGFloat(col) * (cellWidth + spacing)
                    let cellTopY     = startTopY + CGFloat(row) * rowHeight
                    let labelRowTopY = cellTopY + cellHeight + 4
                    let labelRowMidY = labelRowTopY + labelHeight / 2

                    // Checkbox is right-aligned within the cell, vertically centred on the label row
                    // If there's a label, it sits to the left; if not, checkbox is left-aligned
                    let cbX: CGFloat = x + cellWidth - checkboxSize
                    let cbPDFY = pageHeight - (labelRowMidY + checkboxSize / 2)
                    let cbRect = CGRect(x: cbX, y: cbPDFY, width: checkboxSize, height: checkboxSize)

                    let cb = PDFAnnotation(bounds: cbRect, forType: .widget, withProperties: nil)
                    cb.widgetFieldType    = .button
                    cb.widgetControlType  = .checkBoxControl
                    cb.fieldName          = photoID
                    cb.buttonWidgetState  = .offState
                    cb.font               = IRFont.systemFont(ofSize: 9)
                    cb.color              = IRColor(white: 0.3, alpha: 1)
                    page.addAnnotation(cb)
                }
            }

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
    let photoIDs:       [String]
    let pageSize:       CGSize
    let pageNr:         Int
    let margin:         CGFloat
    let spacing:        CGFloat
    let startingIndex:  Int
    let cols:           Int
    let cellWidth:      CGFloat
    let cellHeight:     CGFloat
    let labelHeight:    CGFloat
    let checkboxSize:   CGFloat
    let showNumbers:    Bool
    let showFileName:   Bool
    let showCheckbox:   Bool
    let title:          String?
    let titleHeight:    CGFloat
    let startTopY:      CGFloat

    func draw(in ctx: CGContext) {
        let w = pageSize.width
        let h = pageSize.height

        func pdfY(_ topY: CGFloat) -> CGFloat {
            h - topY
        }

        // Background
        ctx.setFillColor(IRColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // ── Title (page 1 only) ──────────────────────────────────────────────
        if let title {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: IRFont.boldSystemFont(ofSize: 18),
                .foregroundColor: IRColor.black
            ]
            let str      = NSAttributedString(string: title, attributes: attrs)
            let line     = CTLineCreateWithAttributedString(str)
            // Baseline = margin + titleHeight (same anchor used by buildPDF for startTopY)
            let baseline = pdfY(margin + titleHeight)
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: margin, y: baseline)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }

        let rowHeight = cellHeight
            + ((showNumbers || showFileName || showCheckbox) ? labelHeight + 8 : 0)
            + spacing

        for (i, img) in images.enumerated() {
            let col      = i % cols
            let row      = i / cols
            let x        = margin + CGFloat(col) * (cellWidth + spacing)
            let cellTopY = startTopY + CGFloat(row) * rowHeight   // ← shared origin

            // ── Image ────────────────────────────────────────────────────────
            let cellPDFRect = CGRect(x: x,
                                     y: pdfY(cellTopY + cellHeight),
                                     width: cellWidth,
                                     height: cellHeight)
            ctx.setFillColor(IRColor(white: 0.92, alpha: 1).cgColor)
            ctx.fill(cellPDFRect)

            #if os(macOS)
            let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #elseif os(iOS)
            let cgImg = img.cgImage
            #endif
            if let cgImg {
                let imgW  = CGFloat(cgImg.width)
                let imgH  = CGFloat(cgImg.height)
                let scale = min(cellWidth / imgW, cellHeight / imgH)
                let dw = imgW * scale, dh = imgH * scale
                let dx = cellPDFRect.minX + (cellWidth      - dw) / 2
                let dy = cellPDFRect.minY + (cellHeight - dh) / 2
                ctx.draw(cgImg, in: CGRect(x: dx, y: dy, width: dw, height: dh))
            }

            // ── Label row (label + checkbox on the same line) ────────────────
            // The label row sits just below the image.
            // labelRowTopY is the top of the row in top-left space.
            let labelRowTopY = cellTopY + cellHeight + 4
            // Vertical centre of the label row
            let labelRowMidY = labelRowTopY + labelHeight / 2
            let labelBaseline = pdfY(labelRowMidY + 4)   // +4 ≈ half cap-height

            let attrs: [NSAttributedString.Key: Any] = [
                .font: IRFont.systemFont(ofSize: 9),
                .foregroundColor: IRColor.darkGray
            ]

            if showNumbers, i < photoNames.count {
                let str = NSAttributedString(string: "#\(startingIndex+i+1) • \(photoNames[i])", attributes: attrs)
                let line = CTLineCreateWithAttributedString(str)
                ctx.saveGState()
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: x, y: labelBaseline)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            }
        }

        if true {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: IRFont.systemFont(ofSize: 9),
                .foregroundColor: IRColor.darkGray
            ]
            let str = NSAttributedString(string: "Page \(pageNr)", attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: margin, y: margin)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
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
