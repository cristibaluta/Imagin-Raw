//
//  FilesExtensions.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 09.03.2026.
//

import Foundation

enum FilesExtensions {
    static let raw: Set<String> = [
        "arw", "orf", "rw2", "cr2", "cr3", "crw", "nef", "nrw",
        "srf", "sr2", "raw", "raf", "pef", "ptx", "dng", "3fr",
        "fff", "iiq", "mef", "mos", "x3f", "srw", "dcr", "kdc",
        "k25", "kc2", "mrw", "erf", "bay", "ndd", "sti", "rwl", "r3d"
    ]

    static let nonRaw: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif"]

    /// All supported image extensions (RAW + non-RAW)
    static let all: Set<String> = raw.union(nonRaw)
}
