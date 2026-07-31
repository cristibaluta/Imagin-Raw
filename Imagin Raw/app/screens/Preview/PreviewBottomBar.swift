//
//  PreviewBottomBar.swift
//  Imagin Raw
//

import SwiftUI

struct PreviewBottomBar: View {

    @ObservedObject var viewModel: PreviewViewModel
    @Binding var showExportPanel: Bool
    @Binding var gridType: GridType

    var body: some View {
        HStack(spacing: 0) {
            if let photo = viewModel.photos?.first, let exifData = photo.exif {
                if viewModel.exifIsExpanded || gridType == .large {
                    ExifExtendedView(exifData: exifData,
                                     fileSize: photo.fileSizeBytes,
                                     dateCreated: photo.dateCreated,
                                     gridType: $gridType)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if gridType != .large {
                            viewModel.toggleExifExpanded()
                        }
                    }
                } else {
                    ExifCompactView(exifData: exifData,
                                    fileSize: photo.fileSizeBytes,
                                    dateCreated: photo.exif?.dateCaptured)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleExifExpanded()
                    }
                }

                Spacer()
            }

            VStack(spacing: 0) {
                if viewModel.exifIsExpanded || gridType == .large {
                    Spacer()
                }

                HStack(spacing: 0) {
                    if viewModel.photos?.count == 1 {
                        separator
                        zoomButton
                        separator
                        exportButton
                    } else if viewModel.photos?.count ?? 0 > 1 {
                        separator
                        pdfButton
                        separator
                        videoButton
                    }
                }
                .frame(height: 40)
            }
        }
        .frame(height: gridType == .large ? 142 : (viewModel.exifIsExpanded ? 88 : 40))
    }

    @ViewBuilder
    private var separator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 14)
    }

    @ViewBuilder
    private var zoomButton: some View {
        Button(action: {
            if viewModel.fullResImage != nil {
                viewModel.exitZoom()
            } else {
                viewModel.loadFullResolution()
            }
        }) {
            ZStack {
                if viewModel.isLoadingFullRes {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
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
    }

    @ViewBuilder
    private var exportButton: some View {
        Button(action: {
            showExportPanel.toggle()
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

    @ViewBuilder
    private var pdfButton: some View {
        Button(action: {
            showExportPanel.toggle()
        }) {
            Image(systemName: "text.rectangle.page")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(showExportPanel ? .accentColor : .secondary)
                .padding(.trailing, 12)
                .padding(.leading, 10)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Create PDF from selected photos")
    }

    @ViewBuilder
    private var videoButton: some View {
        Button(action: {
            showExportPanel.toggle()
        }) {
            Image(systemName: "movieclapper")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(showExportPanel ? .accentColor : .secondary)
                .padding(.trailing, 12)
                .padding(.leading, 10)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Create movie clip from selected photos")
    }
}
