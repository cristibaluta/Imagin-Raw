//
//  LargePreviewView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct Layout {
    let dispCanvasW: CGFloat
    let dispCanvasH: CGFloat
    let dispImgW: CGFloat
    let dispImgH: CGFloat
    let imgOffX: CGFloat
    let imgOffY: CGFloat
}

struct LargePreviewView: View {
    let photo: PhotoItem
    @StateObject private var model = LargePreviewViewModel()
    @State private var showExportPanel = false
    @State private var exportRatio: ExportAspectRatio = ExportAspectRatio(rawValue: appPrefs.string(.exportRatio)) ?? .r4x5
    @State private var exportPadding: Double = appPrefs.get(.exportPadding)
    @State private var exportAlignment: ExportAlignment = ExportAlignment(rawValue: appPrefs.string(.exportAlignment)) ?? .center
    @State private var mousePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        if photo.isVideo {
            VideoPreviewView(photo: photo)
        } else {
            photoPreviewBody
        }
    }

    @ViewBuilder
    private var photoPreviewBody: some View {
        VStack(spacing: 0) {
            // Image area
            GeometryReader { geo in
                ZStack(alignment: .center) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let fullRes = model.fullResImage {
                        #if os(macOS)
                        ZoomPanView(image: fullRes, initialMousePosition: mousePosition)
                        #endif
                    } else if let nsImage = model.preview {
                        HStack {
                            if !model.alignToTopLeft { Spacer(minLength: 0) }
                            VStack {
                                if !model.alignToTopLeft { Spacer(minLength: 0) }
                                if showExportPanel {
                                    ExportCanvasPreview(
                                        image: nsImage,
                                        geo: geo,
                                        targetRatio: exportRatio,
                                        padding: exportPadding,
                                        alignment: exportAlignment
                                    )
                                } else {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFit()
                                }
                                //.animation(.easeInOut(duration: 0.35), value: showExportPanel)
                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
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
                                    padding: $exportPadding,
                                    alignment: $exportAlignment
                                )
                                .padding(12)
                            }
                        }
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: showExportPanel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                #if os(macOS)
                .background(MouseTrackingView(onMouseMoved: { point, viewSize in
                    let nx = viewSize.width  > 0 ? max(0, min(1, point.x / viewSize.width))  : 0.5
                    let ny = viewSize.height > 0 ? max(0, min(1, 1 - point.y / viewSize.height)) : 0.5
                    mousePosition = CGPoint(x: nx, y: ny)
                }))
                #endif
            }

            // EXIF bottom bar
            if let exifInfo = model.exifInfo {
                PreviewBottomBar(photo: photo,
                                 exifInfo: exifInfo,
                                 model: model,
                                 showExportPanel: $showExportPanel)
            }
        }
        .onAppear {
            model.setPhoto(photo)
        }
        .onChange(of: photo) { _, newPhoto in
            model.setPhoto(newPhoto)
            showExportPanel = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZoom)) { _ in
            if model.fullResImage != nil {
                model.exitZoom()
            } else if !model.isLoadingFullRes {
                model.loadFullResolution()
            }
        }
        .onChange(of: exportRatio) { _, newVal in
            appPrefs.set(newVal.rawValue, forKey: .exportRatio)
        }
        .onChange(of: exportPadding) { _, newVal in
            appPrefs.set(newVal, forKey: .exportPadding)
        }
        .onChange(of: exportAlignment) { _, newVal in
            appPrefs.set(newVal.rawValue, forKey: .exportAlignment)
        }
    }
}

// MARK: - Live Canvas Preview

extension Notification.Name {
    static let toggleZoom = Notification.Name("ro.imagin.raw.toggleZoom")
}

private func exportPixelSize(for image: IRImage?) -> CGSize {
    guard let image else {
        return .zero
    }
    #if os(macOS)
    if let rep = image.representations.first as? NSBitmapImageRep {
        return CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
    }
    if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
    }
    #endif
    return image.size
}

private struct ExportCanvasPreview: View, Animatable {
    let image: IRImage
    var geo: GeometryProxy
    let targetRatio: ExportAspectRatio
    var padding: Double
    let alignment: ExportAlignment

    var animatableData: Double {
        get { padding }
        set { padding = newValue }
    }

    private let pixelSize: CGSize

    init(image: IRImage, geo: GeometryProxy, targetRatio: ExportAspectRatio, padding: Double, alignment: ExportAlignment) {
        self.image = image
        self.geo = geo
        self.targetRatio = targetRatio
        self.padding = padding
        self.alignment = alignment
        #if os(macOS)
        if let rep = image.representations.first as? NSBitmapImageRep {
            self.pixelSize = CGSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
        } else if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.pixelSize = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        } else {
            self.pixelSize = image.size
        }
        #else
        self.pixelSize = image.size
        #endif
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

        let scale = min(available.width / canvasW, available.height / canvasH)
        let dispCanvasW = canvasW * scale
        let dispCanvasH = canvasH * scale
        let dispImgW = src.width * scale
        let dispImgH = src.height * scale

        // Horizontal offset based on alignment
        let extraSpace = (dispCanvasW - dispImgW) / 2
        let imgOffX: CGFloat
        switch alignment {
            case .left:   imgOffX = -extraSpace + pad * scale
            case .center: imgOffX = 0
            case .right:  imgOffX = extraSpace - pad * scale
        }
        let imgOffY = 0.0
//        print("alignment: \(alignment), dispCanvas: \(dispCanvasW) \(dispCanvasH), dispImg: \(dispImgW) \(dispImgH), imgOff: \(imgOffX) \(imgOffY)")

        return Layout(
            dispCanvasW: dispCanvasW, dispCanvasH: dispCanvasH,
            dispImgW: dispImgW, dispImgH: dispImgH,
            imgOffX: imgOffX, imgOffY: imgOffY
        )
    }

    var body: some View {
        let _ = Self._printChanges()
        let l = layout(in: geo.size)
        ZStack {
            Rectangle()
                .fill(Color.black)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: l.dispImgW, height: l.dispImgH)
                .offset(x: l.imgOffX, y: l.imgOffY)
        }
        .frame(width: l.dispCanvasW, height: l.dispCanvasH)
    }
}
