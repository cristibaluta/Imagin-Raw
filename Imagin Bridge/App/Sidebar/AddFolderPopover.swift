//
//  AddFolderPopover.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 02.02.2026.
//

import SwiftUI

struct AddFolderPopover: View {
    @EnvironmentObject var filesModel: FilesModel
    let onAddVolumes: () -> Void
    let onAddCustomFolder: () -> Void

    private var volumesAlreadyAdded: Bool {
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        return filesModel.rootFolders.contains { $0.url == volumesURL }
    }

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 4) {
                // Volumes option
                Button(action: onAddVolumes) {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
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

                Divider()

                // Custom folder option
                Button(action: onAddCustomFolder) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose Folder...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)

                            Text("Browse and select any folder")
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

            Spacer().frame(height: 4)
        }
        .frame(width: 250)
    }
}
