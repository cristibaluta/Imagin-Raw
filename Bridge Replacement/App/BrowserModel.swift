//
//  BrowserModel.swift
//  Bridge Replacement
//
//  Created by Cristian Baluta on 30.01.2026.
//
import Foundation
import CoreServices

func loadFolderTree(at url: URL, maxDepth: Int = 2, currentDepth: Int = 0) -> FolderItem {
    print("Load folder tree: \(url.path) currentDepth: \(currentDepth)")
    var children: [FolderItem] = []

    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
    let fm = FileManager.default

    if let items = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
    ) {
        let sortedFolders = items
            .compactMap { item -> URL? in
                guard let values = try? item.resourceValues(forKeys: keys), values.isDirectory == true else { return nil }
                return item
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

        for folder in sortedFolders {
            if currentDepth < maxDepth {
                // Load recursively up to maxDepth
                children.append(loadFolderTree(at: folder, maxDepth: maxDepth, currentDepth: currentDepth + 1))
            } else {
                // At maxDepth, just check if this folder has subfolders to determine if it should be expandable
                let hasSubfolders = hasDirectSubfolders(at: folder)
                children.append(FolderItem(
                    url: folder,
                    children: hasSubfolders ? [] : nil // Empty array means "expandable but not loaded", nil means "no children"
                ))
            }
        }
    }

    return FolderItem(
        url: url,
        children: children.isEmpty ? nil : children
    )
}

func hasDirectSubfolders(at url: URL) -> Bool {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
    let fm = FileManager.default

    guard let items = try? fm.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
    ) else { return false }

    // Check if any item is a directory
    for item in items {
        if let values = try? item.resourceValues(forKeys: keys), values.isDirectory == true {
            return true
        }
    }
    return false
}

func loadFolderChildren(for folder: FolderItem) -> [FolderItem] {
    // Load children on demand (2 levels deep from this folder)
    let childTree = loadFolderTree(at: folder.url, maxDepth: 2, currentDepth: 0)
    return childTree.children ?? []
}


func loadPhotos(in folder: FolderItem?) -> [PhotoItem] {
    guard let folder else { return [] }

    let fm = FileManager.default
    let allowed = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "arw", "orf", "rw2",
                   "cr2", "cr3", "crw", "nef", "nrw", "srf", "sr2", "raw", "raf",
                   "pef", "ptx", "dng", "3fr", "fff", "iiq", "mef", "mos", "x3f",
                   "srw", "dcr", "kdc", "k25", "kc2", "mrw", "erf", "bay", "ndd",
                   "sti", "rwl", "r3d"]

    let files = (try? fm.contentsOfDirectory(
        at: folder.url,
        includingPropertiesForKeys: [.creationDateKey],
        options: [.skipsHiddenFiles]
    )) ?? []

    // Separate image files from XMP files
    let imageFiles = files.filter { allowed.contains($0.pathExtension.lowercased()) }
    let xmpFiles = files.filter { $0.pathExtension.lowercased() == "xmp" }

    // Create a dictionary for XMP lookup by base filename
    var xmpLookup: [String: String] = [:]
    for xmpFile in xmpFiles {
        let baseName = xmpFile.deletingPathExtension().lastPathComponent
        if let xmpContent = try? String(contentsOf: xmpFile, encoding: .utf8) {
            xmpLookup[baseName] = xmpContent
        }
    }

    // Create PhotoItems with matched XMP content
    return imageFiles
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { imageFile in
            let baseName = imageFile.deletingPathExtension().lastPathComponent

            // Get creation date from the file attributes we already retrieved
            let creationDate = (try? imageFile.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

            if let xmpContent = xmpLookup[baseName] {
                let xmp = XmpParser.parseMetadata(from: xmpContent)
                return PhotoItem(path: imageFile.path, xmp: xmp, dateCreated: creationDate)
            } else {
                return PhotoItem(path: imageFile.path, xmp: nil, dateCreated: creationDate)
            }
        }
}


@MainActor
final class BrowserModel: ObservableObject {
    @Published var rootFolders: [FolderItem]
    @Published var selectedFolder: FolderItem? {
        didSet {
            loadPhotosForSelectedFolder()
        }
    }
    @Published var selectedPhoto: PhotoItem?
    @Published var photos: [PhotoItem] = []

    init() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let volumesURL = URL(fileURLWithPath: "/Volumes")

        self.rootFolders = [
            loadFolderTree(at: volumesURL, maxDepth: 1), // Only 1 level for volumes to avoid scanning large drives
            loadFolderTree(at: homeURL, maxDepth: 2)     // 2 levels for home directory
        ]
    }

    func loadChildrenOnDemand(for folder: FolderItem) {
        // Find the folder in our tree and update its children
        updateFolderChildren(folder: folder, in: &rootFolders)
    }

    private func updateFolderChildren(folder: FolderItem, in folders: inout [FolderItem]) {
        for i in 0..<folders.count {
            if folders[i].url == folder.url {
                // Found the folder, load its children
                let updatedChildren = loadFolderChildren(for: folder)
                folders[i] = FolderItem(url: folder.url, children: updatedChildren.isEmpty ? nil : updatedChildren)
                return
            } else if let children = folders[i].children {
                // Recursively search in children
                var mutableChildren = children
                updateFolderChildren(folder: folder, in: &mutableChildren)
                folders[i] = FolderItem(url: folders[i].url, children: mutableChildren)
            }
        }
    }

    private func loadPhotosForSelectedFolder() {
        photos = loadPhotos(in: selectedFolder)
    }
}
