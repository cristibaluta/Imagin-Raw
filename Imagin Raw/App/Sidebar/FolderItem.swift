//
//  FolderItem.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//


import Foundation

struct FolderItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var children: [FolderItem]? = nil
    var bookmarkData: Data? = nil // Security-scoped bookmark data for sandboxed access
    var displayName: String? = nil  // custom label for virtual / PhotoKit nodes

    var title: String { displayName ?? url.lastPathComponent }

    init(url: URL, children: [FolderItem]? = nil, bookmarkData: Data? = nil, displayName: String? = nil) {
        self.url = url
        self.children = children
        self.bookmarkData = bookmarkData
        self.displayName = displayName
    }
}
