//
//  FolderRowView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import SwiftUI

struct FolderRowView: View {
    @EnvironmentObject var fileSystemModel: FileSystemModel
    @EnvironmentObject var appState: AppState
    let folder: FolderItem
    @Binding var expandedFolders: Set<URL>
    @Binding var selectedFolder: FolderItem?
    let saveExpandedState: () -> Void
    let onDoubleClick: () -> Void
    let isRootFolder: Bool
    let isVolumeFolder: Bool
    /// Depth of this folder: 0 = root, 1 = first level inside root, 2+ = deeper
    let depth: Int

    private var isExpanded: Bool {
        expandedFolders.contains(folder.url)
    }

    private var hasChildren: Bool {
        return folder.children != nil
    }

    private var folderColor: Color {
        if isRootFolder {
            // Dark purple for root folders (user-added folders)
            return Color("PurpleThemeColor")
        } else if hasChildren {
            // Regular blue for subfolders with children
            return Color.blue
        } else {
            // Light blue for leaf subfolders
            return Color(red: 139/255, green: 206/255, blue: 248/255)
        }
    }

    private var folderIcon: String {
        if folder.url.isPhotoKitAlbum {
            return "photo.stack"
        }
        if isEjectable {
            return "externaldrive.fill"
        }
        return "folder.fill"
    }

    private var isEjectable: Bool {
        isVolumeFolder && depth == 1
    }

    private var needsToLoadChildren: Bool {
        // Check if this folder has an empty children array (placeholder for expandable but unloaded)
        return folder.children?.isEmpty == true
    }

    // Get the volume path (first component after /Volumes/)
    private var volumePath: String? {
        let path = folder.url.path
        guard path.hasPrefix("/Volumes/") else {
            return nil
        }

        // Extract volume name: /Volumes/MyDrive/... -> /Volumes/MyDrive
        let components = path.components(separatedBy: "/")
        if components.count >= 3 {
            return "/Volumes/\(components[2])"
        }
        return nil
    }

    private func sortedChildren(_ children: [FolderItem]) -> [FolderItem] {
        // depth == 0 means this is a root folder, so its children are level 1.
        // depth == 1 means children are level 2, etc.
        let childDepth = depth + 1
        let sortByDate: Bool
        switch fileSystemModel.sidebarSortOption {
        case .name:
            sortByDate = false        // all levels by name
        case .dateCreated:
            sortByDate = true         // all levels by date
        case .nameThenDate:
            sortByDate = childDepth >= 2  // level 1 by name, level 2+ by date
        }

        if sortByDate {
            return children.sorted { a, b in
                let dateA = (try? a.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let dateB = (try? b.url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return dateA < dateB
            }
        } else {
            return children.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    // TODO: This should not be in the view
    #if os(macOS)
    private func ejectVolume() {
        guard let volumePath else {
            return
        }

        let volumeURL = URL(fileURLWithPath: volumePath)

        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Failed to Eject"
                alert.informativeText = "Could not eject '\(volumeURL.lastPathComponent)': \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    #endif

    var body: some View {
        if hasChildren {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { newValue in
                        if newValue {
                            expandedFolders.insert(folder.url)
                            // Trigger on-demand loading if this folder needs its children loaded
                            if needsToLoadChildren {
                                #if os(macOS)
                                fileSystemModel.loadChildrenOnDemand(for: folder)
                                #endif
                            }
                        } else {
                            expandedFolders.remove(folder.url)
                        }
                        saveExpandedState()
                    }
                )
            ) {
                ForEach(sortedChildren(folder.children ?? [])) { childFolder in
                    FolderRowView(folder: childFolder,
                                  expandedFolders: $expandedFolders,
                                  selectedFolder: $selectedFolder,
                                  saveExpandedState: saveExpandedState,
                                  onDoubleClick: onDoubleClick,
                                  isRootFolder: false,
                                  isVolumeFolder: isVolumeFolder,
                                  depth: depth + 1
                    )
                }
            } label: {
                buildFolderLabel
            }
        } else {
            buildFolderLabel
        }
    }

    private var buildFolderLabel: some View {
        HStack {
            Label {
                Text(folder.title)
            } icon: {
                Image(systemName: folderIcon)
                    .foregroundStyle(folderColor)
            }

            if isEjectable {
                Spacer()

                Button {
                    ejectVolume()
                } label: {
                    Image(systemName: "eject")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .tag(folder)
        .onTapGesture {
            #if os(iOS)
            RCLog("👆 [Sidebar] tap leaf: \(folder.title) already=\(selectedFolder?.url == folder.url)")
            if selectedFolder?.url == folder.url {
                selectedFolder = nil
                DispatchQueue.main.async {
                    selectedFolder = folder
                }
            } else {
                selectedFolder = folder
            }
            #else
            appState.includeSubfolders = false
            selectedFolder = folder
            #endif
        }
        .onDoubleClick {
            onDoubleClick()
        }
        #if os(macOS)
        .contextMenu {
            Button(action: {
                appState.includeSubfolders = true
                selectedFolder = folder
            }) {
                Label("Open Folder + Subfolders", systemImage: "")
            }

            Divider()

            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.url.path)
            }) {
                Label("Show in Finder", systemImage: "")
            }

            Button(action: {
                let cacheURL = appState.thumbnailsCacheManager.cacheDir(folderUrl: folder.url)
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cacheURL.path)
            }) {
                Label("Show Cache in Finder", systemImage: "")
            }

            Button(role: .destructive, action: {
                Task.detached(priority: .background) {
                    await appState.thumbnailsCacheManager.purgeCache(folderURL: folder.url)
                    await appState.previewsCacheManager.purgeCache(folderURL: folder.url)
                    await appState.fullResCacheManager.purgeCache(folderURL: folder.url)
                }
            }) {
                Label("Purge Cache", systemImage: "trash")
            }

            // Only show eject option for root folders in /Volumes
            if isEjectable {
                Divider()
                Button(action: {
                    ejectVolume()
                }) {
                    Label("Eject", systemImage: "eject")
                }
            }
        }
        #endif
    }
}
