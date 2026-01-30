//
//  BrowserModel.swift
//  Bridge Replacement
//
//  Created by Cristian Baluta on 30.01.2026.
//

func loadFolderTree(at url: URL) -> FolderItem {
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
            children.append(loadFolderTree(at: folder))
        }
    }

    return FolderItem(
        url: url,
        children: children.isEmpty ? nil : children
    )
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
        includingPropertiesForKeys: nil,
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
            if let xmpContent = xmpLookup[baseName] {
                let xmp = XmpParser.parseMetadata(from: xmpContent)
                return PhotoItem(path: imageFile.path, xmp: xmp)
            } else {
                return PhotoItem(path: imageFile.path, xmp: nil)
            }
        }
}


@MainActor
final class BrowserModel: ObservableObject {
    @Published var rootFolder: FolderItem
    @Published var selectedFolder: FolderItem? {
        didSet {
            loadPhotosForSelectedFolder()
        }
    }
    @Published var selectedPhoto: PhotoItem?
    @Published var photos: [PhotoItem] = []

    init() {
        let pictures = FileManager.default.urls(
            for: .picturesDirectory,
            in: .userDomainMask
        ).first!

        self.rootFolder = loadFolderTree(at: pictures)
    }

    private func loadPhotosForSelectedFolder() {
        photos = loadPhotos(in: selectedFolder)
    }
}
