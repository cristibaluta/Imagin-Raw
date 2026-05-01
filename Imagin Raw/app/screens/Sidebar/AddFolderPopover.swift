//
//  AddFolderPopover.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 02.02.2026.
//

import SwiftUI

struct AddFolderPopover: View {
    @EnvironmentObject var filesModel: FilesModel
    let onAddVolumes: () -> Void
    let onAddPhotoLibrary: () -> Void
    let onAddCustomFolder: () -> Void

    private var volumesAlreadyAdded: Bool {
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        return filesModel.rootFolders.contains { $0.url == volumesURL }
    }

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 4) {
                buttonVolumes
                Divider()
                buttonPhotoLibrary
                Divider()
                buttonFolder
            }
            Spacer().frame(height: 4)
        }
        .frame(width: 250)
    }

    private var buttonVolumes: some View {
        Button(action: onAddVolumes) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 16))
                    .foregroundColor(Color("PurpleColor"))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Volumes")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)

                    Text("External drives and network volumes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if volumesAlreadyAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(volumesAlreadyAdded)
        .opacity(volumesAlreadyAdded ? 0.6 : 1.0)
    }

    private var buttonPhotoLibrary: some View {
        Button(action: onAddPhotoLibrary) {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16))
                    .foregroundColor(Color("PurpleColor"))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Photos Library")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)

                    Text("Browse your Apple Photos library")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if filesModel.isPhotoLibraryEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(filesModel.isPhotoLibraryEnabled)
        .opacity(filesModel.isPhotoLibraryEnabled ? 0.6 : 1.0)
    }

    private var buttonFolder: some View {
        Button(action: onAddCustomFolder) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 16))
                    .foregroundColor(Color("PurpleColor"))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose Folder...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)

                    Text("Any folder from disk or iCloud")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
