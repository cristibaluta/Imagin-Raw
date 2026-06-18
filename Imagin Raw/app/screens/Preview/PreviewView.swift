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

struct PreviewView: View {

    @ObservedObject var viewModel: PreviewViewModel

    @State private var showExportPanel = false
    @State private var showEditPanel = false
    @State private var gridType: ThumbGridViewModel.GridType = ThumbGridViewModel.GridType(rawValue: appPrefs.string(.gridType)) ?? .small
    @State private var exportRatio: ExportAspectRatio = ExportAspectRatio(rawValue: appPrefs.string(.exportRatio)) ?? .r4x5
    @State private var exportAlignment: ExportAlignment = ExportAlignment(rawValue: appPrefs.string(.exportAlignment)) ?? .center
    @State private var exportPadding: Double = appPrefs.get(.exportPadding)
    @State private var showAFPoint: Bool = appPrefs.get(.showAFPoint)
    @State private var mousePosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    private var effectiveAlignToTopLeft: Bool {
        gridType == .large ? true : viewModel.alignToTopLeft
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing: 0) {
            // Separator
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)

            // Content
            if let photo = viewModel.photo, photo.isVideo {
                VideoPreviewView(photo: photo)
            } else {
                photoPreviewBody
                bottomBar
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
        .onChange(of: showAFPoint) { _, newVal in
            appPrefs.set(newVal, forKey: .showAFPoint)
        }
//        .sheet(isPresented: $showEditPanel) {
//            if let preview = viewModel.preview {
//                PerspectiveCorrectionView(image: preview) { corrected in
//                    showEditPanel = false
//                    // TODO: store corrected image for export
//                }
//                .frame(minWidth: 700, minHeight: 500)
//            }
//        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleZoom)) { _ in
            if viewModel.fullResImage != nil {
                viewModel.exitZoom()
            } else if !viewModel.isLoadingFullRes {
                viewModel.loadFullResolution()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            gridType = ThumbGridViewModel.GridType(rawValue: appPrefs.string(.gridType)) ?? .small
        }
    }

    @ViewBuilder
    private var photoPreviewBody: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                if let fullRes = viewModel.fullResImage {
                    #if os(macOS)
                    ZoomPanView(image: fullRes, initialMousePosition: mousePosition)
                    #endif
                } else if let nsImage = viewModel.image {
                    HStack {
                        if !effectiveAlignToTopLeft { Spacer(minLength: 0) }
                        VStack {
                            if !effectiveAlignToTopLeft { Spacer(minLength: 0) }
                            if showExportPanel {
                                ExportCanvasPreview(image: nsImage,
                                                    geo: geo,
                                                    targetRatio: exportRatio,
                                                    padding: exportPadding,
                                                    alignment: exportAlignment
                                )
                            } else {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
//                                    .overlay(showAFPoint ? FocusPointOverlay(nsImage: nsImage,
//                                                             focusResult: parseOlympusAFPoint(from: URL(fileURLWithPath: photo.path))) : nil)
//                                    .overlay(FocusPointOverlay(nsImage: nsImage,
//                                                               focusResult: parsePanasonicAFPoint(from: URL(fileURLWithPath: photo.path))))
                            }
                            //.animation(.easeInOut(duration: 0.35), value: showExportPanel)
                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                } else if viewModel.isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Failed to load image")
                        .foregroundColor(.secondary)
                }

                // Alignment button
                VStack {
                    HStack {
                        if !showExportPanel && viewModel.fullResImage == nil && gridType != .large {
                            Button(action: { viewModel.toggleAlignment() }) {
                                Image(systemName: effectiveAlignToTopLeft ? "arrow.down.right.square" : "arrow.up.left.square")
                                    .font(.title2)
                                    .foregroundColor(effectiveAlignToTopLeft ? .white.opacity(0.4) : .gray)
                                    .padding()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(effectiveAlignToTopLeft ? "Center image" : "Align to top-left")
                        }
                        Spacer()
                    }
                    Spacer()
                }

                // Export panel overlay — bottom-right
                if showExportPanel, let photo = viewModel.photo {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ExportPanelView(photo: photo,
                                            pixelSize: exportPixelSize(for: viewModel.image),
                                            isPresented: $showExportPanel,
                                            selectedRatio: $exportRatio,
                                            padding: $exportPadding,
                                            alignment: $exportAlignment)
                            .frame(width: 280)
                            .padding(12)
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: showExportPanel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                if viewModel.isLoadingFullRes {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            #if os(macOS)
            .background(MouseTrackingView(onMouseMoved: { point, viewSize in
                let nx = viewSize.width  > 0 ? max(0, min(1, point.x / viewSize.width))  : 0.5
                let ny = viewSize.height > 0 ? max(0, min(1, 1 - point.y / viewSize.height)) : 0.5
                mousePosition = CGPoint(x: nx, y: ny)
            }))
            #endif
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        // EXIF bottom bar or vertical column
        if let photo = viewModel.photo, let exifInfo = viewModel.exifInfo {
            if gridType == .large {
                ExifColumnView(exifInfo: exifInfo, fileSize: photo.fileSizeBytes, dateCreated: photo.dateCreated)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 14)
                    Button(action: {
                        if viewModel.fullResImage != nil {
                            viewModel.exitZoom()
                        } else {
                            viewModel.loadFullResolution()
                        }
                    }) {
                        ZStack {
                            if viewModel.isLoadingFullRes {
                                ProgressView().controlSize(.small).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: viewModel.fullResImage != nil ? "minus.magnifyingglass" : "plus.magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(viewModel.fullResImage != nil ? .accentColor : .secondary)
                            }
                        }
                        .frame(width: 20, height: 20)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.isLoadingFullRes)
                    .help(viewModel.fullResImage != nil ? "Exit zoom (Z)" : "Zoom to 100% (Z)")

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 14)

                    Button(action: { showExportPanel.toggle() }) {
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
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
                PreviewBottomBar(photo: photo,
                                 exifInfo: exifInfo,
                                 model: viewModel,
                                 showAFPoint: $showAFPoint,
                                 showEditPanel: $showEditPanel,
                                 showExportPanel: $showExportPanel)
            }
        }
    }
}

struct FocusPointOverlay: View {
    let nsImage: IRImage
    let focusResult: OlympusAFPoint?

    var body: some View {
        GeometryReader { geo in
            if let point = focusResult {
                let (renderedSize, offset) = renderedImageRect(in: geo.size)
                let boxX = offset.x + (point.cx - point.width  / 2) * renderedSize.width
                let boxY = offset.y + (point.cy - point.height / 2) * renderedSize.height
                let boxW = point.width  * renderedSize.width
                let boxH = point.height * renderedSize.height

                Rectangle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: boxW, height: boxH)
                    .position(x: boxX + boxW / 2, y: boxY + boxH / 2)
            }
        }
    }

    private func renderedImageRect(in containerSize: CGSize) -> (size: CGSize, offset: CGPoint) {
        let imageAspect     = nsImage.size.width / nsImage.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let w = containerSize.width
            let h = containerSize.width / imageAspect
            return (CGSize(width: w, height: h), CGPoint(x: 0, y: (containerSize.height - h) / 2))
        } else {
            let h = containerSize.height
            let w = containerSize.height * imageAspect
            return (CGSize(width: w, height: h), CGPoint(x: (containerSize.width - w) / 2, y: 0))
        }
    }
}

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
