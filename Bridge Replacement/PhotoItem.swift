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
    let xmpContent: String?
    let label: String?

    init(path: String, xmpContent: String? = nil) {
        self.path = path
        self.xmpContent = xmpContent
        // Parse the label from XMP content
        self.label = xmpContent != nil ? XmpParser.extractLabel(from: xmpContent!) : nil
    }
}
