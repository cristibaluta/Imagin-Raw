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

    static let jpg: Set<String> = ["jpg", "jpeg"]

    static let other: Set<String> = ["png", "heic", "tiff", "tif"]

    static let video: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "hevc"]

    /// All supported extensions (RAW + JPG + other + video)
    static let all: Set<String> = raw.union(jpg).union(other).union(video)
}
