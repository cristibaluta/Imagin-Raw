//
//  PreviewBottomBar.swift
//  Imagin Raw
//

import SwiftUI

struct PreviewBottomBar: View {
    let photo: PhotoItem
    let exifInfo: ExifInfo
    let model: PreviewViewModel
    @Binding var showAFPoint: Bool
    @Binding var showEditPanel: Bool
    @Binding var showExportPanel: Bool

    private var supportsAFPoint: Bool {
        RawBrand.afPointSupported.contains(FilesExtensions.brand(forPath: photo.path))
    }

    var body: some View {
        HStack(spacing: 0) {
//            ExifCompactView(exifInfo: exifInfo, fileSize: photo.fileSizeBytes, dateCreated: photo.dateCreated)
            ExifExtendedView(exifInfo: exifInfo, fileSize: photo.fileSizeBytes, dateCreated: photo.dateCreated)
            Spacer()

            VStack(spacing: 0) {
                Spacer()

                HStack(spacing: 0) {
                    // AF point button (only for supported RAW brands)
                    if supportsAFPoint {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 1, height: 14)
                        Button(action: { showAFPoint.toggle() }) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(showAFPoint ? .accentColor : .secondary)
                                .frame(width: 20, height: 20)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(showAFPoint ? "Hide AF point" : "Show AF point")
                    }

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
                    .help(model.fullResImage != nil ? "Exit zoom (Z)" : "Zoom to 100% (Z)")

                    // Edit button
                    //            Rectangle()
                    //                .fill(Color.secondary.opacity(0.25))
                    //                .frame(width: 1, height: 14)
                    //            Button(action: { showEditPanel.toggle() }) {
                    //                Image(systemName: "wand.and.stars")
                    //                    .font(.system(size: 14, weight: .medium))
                    //                    .foregroundColor(showEditPanel ? .accentColor : .secondary)
                    //                    .frame(width: 20, height: 20)
                    //                    .padding(.horizontal, 10)
                    //            }
                    //            .buttonStyle(PlainButtonStyle())
                    //            .help("Edit: perspective correction")

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
            }
        }
        .frame(height: 88)
    }
}
