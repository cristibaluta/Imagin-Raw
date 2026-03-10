//
//  LargePreviewView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct LargePreviewView: View {
    let photo: PhotoItem
    @StateObject private var model = LargePreviewViewModel()
    @State private var showExportPanel = false
    @State private var exportRatio: ExportAspectRatio = ExportAspectRatio(rawValue: appPrefs.string(.exportRatio)) ?? .original
    @State private var exportPadding: Double = appPrefs.get(.exportPadding)
    @State private var mousePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Image area
            ZStack(alignment: model.alignToTopLeft ? .topLeading : .center) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let fullRes = model.fullResImage {
                    let _ = print("🔎 [zoom] rendering ZoomPanView  imageSize=\(fullRes.size)  reps=\(fullRes.representations.count)")
                    ZoomPanView(image: fullRes, initialMousePosition: mousePosition)
                } else if let nsImage = model.preview {
                    // Both views are always in the tree — swap via opacity, no view teardown
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                        .opacity(showExportPanel ? 0 : 1)
                    ExportCanvasPreview(
                        image: nsImage,
                        targetRatio: exportRatio,
                        padding: exportPadding
                    )
                    .opacity(showExportPanel ? 1 : 0)
                } else if model.isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Failed to load image")
                        .foregroundColor(.secondary)
                }

                // Alignment button
                VStack {
                    HStack {
                        if !showExportPanel && model.fullResImage == nil {
                            Button(action: { model.toggleAlignment() }) {
                                Image(systemName: model.alignToTopLeft ? "arrow.down.right.square" : "arrow.up.left.square")
                                    .font(.title2)
                                    .foregroundColor(model.alignToTopLeft ? .white.opacity(0.4) : .gray)
                                    .padding()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(model.alignToTopLeft ? "Center image" : "Align to top-left")
                        }
                        Spacer()
                    }
                    Spacer()
                }

                // Export panel overlay — bottom-right
                if showExportPanel {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ExportPanelView(
                                photo: photo,
                                pixelSize: exportPixelSize(for: model.preview),
                                isPresented: $showExportPanel,
                                selectedRatio: $exportRatio,
                                padding: $exportPadding
                            )
                            .padding(12)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(MouseTrackingView(onMouseMoved: { point, viewSize in
                let nx = viewSize.width  > 0 ? max(0, min(1, point.x / viewSize.width))  : 0.5
                let ny = viewSize.height > 0 ? max(0, min(1, 1 - point.y / viewSize.height)) : 0.5
                mousePosition = CGPoint(x: nx, y: ny)
            }))

            // EXIF bottom bar
            if let exifInfo = model.exifInfo {
                HStack(spacing: 0) {
                    ExifBarView(exifInfo: exifInfo, fileSize: photo.fileSizeBytes)
                    Spacer()

                    // Zoom button
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 14)
                    Button(action: {
                        if model.fullResImage != nil {
                            model.exitZoom()
                        } else {
                            model.loadFullResolution()
                        }
                    }) {
                        ZStack {
                            if model.isLoadingFullRes {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: model.fullResImage != nil ? "minus.magnifyingglass" : "plus.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(model.fullResImage != nil ? .accentColor : .secondary)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(model.isLoadingFullRes)
                    .help(model.fullResImage != nil ? "Exit zoom" : "Zoom to 100% (full resolution)")

                    // Export button
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 14)
                    Button(action: {
                        print("⏱ [export] button tapped showExportPanel=\(showExportPanel) at \(String(format: "%.4f", Date().timeIntervalSinceReferenceDate))")
                        showExportPanel.toggle()
                        print("⏱ [export] toggle done at \(String(format: "%.4f", Date().timeIntervalSinceReferenceDate))")
                    }) {
                        Image(systemName: "rectangle.center.inset.filled")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(showExportPanel ? .accentColor : .secondary)
                            .padding(.trailing, 12)
                            .padding(.leading, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Export: add borders / change canvas")
                }
                .frame(height: 40)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            model.setPhoto(photo)
            isFocused = true
        }
        .onChange(of: photo) { _, newPhoto in
            model.setPhoto(newPhoto)
            showExportPanel = false
            isFocused = true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress("z") {
            if model.fullResImage != nil {
                model.exitZoom()
            } else if !model.isLoadingFullRes {
                model.loadFullResolution()
            }
            return .handled
        }
        .onChange(of: exportRatio) { _, newVal in
            appPrefs.set(newVal.rawValue, forKey: .exportRatio)
        }
        .onChange(of: exportPadding) { _, newVal in
            appPrefs.set(newVal, forKey: .exportPadding)
        }
    }
}

// MARK: - Live Canvas Preview

private func exportPixelSize(for image: NSImage?) -> CGSize {
    guard let image else { return .zero }
    if let rep = image.representations.first as? NSBitmapImageRep {
        return CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
    }
    if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
    }
    return image.size
}

private struct ExportCanvasPreview: View {
    let image: NSImage
    let targetRatio: ExportAspectRatio
    let padding: Double

    /// Computed once at init — avoids calling cgImage() on every layout pass
    private let pixelSize: CGSize

    init(image: NSImage, targetRatio: ExportAspectRatio, padding: Double) {
        self.image = image
        self.targetRatio = targetRatio
        self.padding = padding
        let t = Date()
        if let rep = image.representations.first as? NSBitmapImageRep {
            self.pixelSize = CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
            print("⏱ [ExportCanvasPreview] pixelSize from BitmapRep (instant): \(self.pixelSize)")
        } else if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.pixelSize = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
            print("⏱ [ExportCanvasPreview] pixelSize from cgImage took \(Date().timeIntervalSince(t) * 1000)ms: \(self.pixelSize)")
        } else {
            self.pixelSize = image.size
            print("⏱ [ExportCanvasPreview] pixelSize fallback to image.size: \(self.pixelSize)")
        }
    }

    private struct Layout {
        let dispCanvasW: CGFloat
        let dispCanvasH: CGFloat
        let dispImgW: CGFloat
        let dispImgH: CGFloat
        let imgOffX: CGFloat
        let imgOffY: CGFloat
    }

    private func layout(in available: CGSize) -> Layout {
        let src = pixelSize
        let pad = CGFloat(padding)
        let paddedW = src.width + pad * 2
        let paddedH = src.height + pad * 2

        let canvasW: CGFloat
        let canvasH: CGFloat
        if let ratio = targetRatio.ratio {
            let paddedRatio = paddedW / paddedH
            if paddedRatio > ratio {
                canvasW = paddedW
                canvasH = paddedW / ratio
            } else if paddedRatio < ratio {
                canvasW = paddedH * ratio
                canvasH = paddedH
            } else {
                canvasW = paddedW
                canvasH = paddedH
            }
        } else {
            canvasW = paddedW
            canvasH = paddedH
        }

        let scale = min((available.width - 16) / canvasW, (available.height - 16) / canvasH)
        let dispCanvasW = canvasW * scale
        let dispCanvasH = canvasH * scale
        let dispImgW = src.width * scale
        let dispImgH = src.height * scale

        return Layout(
            dispCanvasW: dispCanvasW, dispCanvasH: dispCanvasH,
            dispImgW: dispImgW, dispImgH: dispImgH,
            imgOffX: (dispCanvasW - dispImgW) / 2,
            imgOffY: (dispCanvasH - dispImgH) / 2
        )
    }

    var body: some View {
        let _ = print("⏱ [ExportCanvasPreview] body evaluated at \(String(format: "%.4f", Date().timeIntervalSinceReferenceDate))")
        GeometryReader { geo in
            let _ = print("⏱ [ExportCanvasPreview] GeometryReader at \(String(format: "%.4f", Date().timeIntervalSinceReferenceDate)) size=\(geo.size)")
            let t0 = Date()
            let l = layout(in: geo.size)
            let _ = print("⏱ [ExportCanvasPreview] layout() took \(Date().timeIntervalSince(t0) * 1000)ms")
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: l.dispCanvasW, height: l.dispCanvasH)
                Image(nsImage: image)
                    .resizable()
                    .frame(width: l.dispImgW, height: l.dispImgH)
                    .offset(x: l.imgOffX, y: l.imgOffY)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .padding(8)
    }
}
