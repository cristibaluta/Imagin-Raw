//
//  PhotoItem.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 29.01.2026.
//

import Foundation

struct PhotoItem: Identifiable, Hashable {
    let id: UUID
    let path: String
    let xmp: XmpMetadata?

    init(path: String, xmp: XmpMetadata? = nil) {
        self.id = UUID()
        self.path = path
        self.xmp = xmp
    }

    // Initializer that preserves the existing ID when updating XMP metadata
    init(id: UUID, path: String, xmp: XmpMetadata?) {
        self.id = id
        self.path = path
        self.xmp = xmp
    }
}
