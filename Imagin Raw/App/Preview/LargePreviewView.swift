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
    @State private var exportRatio: ExportAspectRatio = .original
    @State private var exportPadding: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Image area
            ZStack(alignment: model.alignToTopLeft ? .topLeading : .center) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let nsImage = model.preview {
                    if showExportPanel {
                        // Live export canvas preview
                        ExportCanvasPreview(
                            image: nsImage,
                            targetRatio: exportRatio,
                            padding: exportPadding
                        )
                    } else {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .padding(2)
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
                        if !showExportPanel {
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
                                isPresented: $showExportPanel,
                                selectedRatio: $exportRatio,
                                padding: $exportPadding
                            )
                            .padding(12)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.easeInOut(duration: 0.18), value: showExportPanel)

            // EXIF bottom bar
            if let exifInfo = model.exifInfo {
                HStack(spacing: 0) {
                    ExifBarView(exifInfo: exifInfo, fileSize: photo.fileSizeBytes)
                    Spacer()
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: 14)
                    Button(action: { showExportPanel.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Export")
                                .font(.caption)
                        }
                        .foregroundColor(showExportPanel ? .accentColor : .secondary)
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Export for Instagram")
                }
                .frame(height: 40)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear { model.setPhoto(photo) }
        .onChange(of: photo) { _, newPhoto in
            model.setPhoto(newPhoto)
            showExportPanel = false
        }
    }
}

// MARK: - Live Canvas Preview

private struct ExportCanvasPreview: View {
    let image: NSImage
    let targetRatio: ExportAspectRatio
    let padding: Double

    private struct Layout {
        let canvasW: CGFloat
        let canvasH: CGFloat
        let dispCanvasW: CGFloat
        let dispCanvasH: CGFloat
        let dispImgW: CGFloat
        let dispImgH: CGFloat
        let imgOffX: CGFloat
        let imgOffY: CGFloat
    }

    private func layout(in available: CGSize) -> Layout {
        let srcW = image.size.width
        let srcH = image.size.height
        let pad = CGFloat(padding)
        let paddedW = srcW + pad * 2
        let paddedH = srcH + pad * 2

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
        let dispImgW = srcW * scale
        let dispImgH = srcH * scale

        return Layout(
            canvasW: canvasW, canvasH: canvasH,
            dispCanvasW: dispCanvasW, dispCanvasH: dispCanvasH,
            dispImgW: dispImgW, dispImgH: dispImgH,
            imgOffX: (dispCanvasW - dispImgW) / 2,
            imgOffY: (dispCanvasH - dispImgH) / 2
        )
    }

    var body: some View {
        GeometryReader { geo in
            let l = layout(in: geo.size)
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
