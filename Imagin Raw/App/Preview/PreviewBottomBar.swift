//
//  PreviewBottomBar.swift
//  Imagin Raw
//

import SwiftUI

struct PreviewBottomBar: View {
    let photo: PhotoItem
    let exifInfo: ExifInfo
    let model: LargePreviewViewModel
    @Binding var showExportPanel: Bool

    var body: some View {
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
        .background(Color(NSColor.controlBackgroundColor))
    }
}
