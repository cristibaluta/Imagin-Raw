//
//  PhotoItem.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 29.01.2026.
//

import Foundation

struct PhotoItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let xmp: XmpMetadata?

    init(path: String, xmp: XmpMetadata? = nil) {
        self.path = path
        self.xmp = xmp
    }
}
