//
//  Aliases.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 13.03.2026.
//

#if os(macOS)

import AppKit
import Cocoa

typealias IRImage = NSImage
typealias IRSize = NSSize
typealias IRRect = NSRect
typealias IRColor = NSColor

#elseif os(iOS)

import UIKit

typealias IRImage = UIImage
typealias IRSize = CGSize
typealias IRRect = CGRect
typealias IRColor = UIColor

struct NSEvent {
    struct ModifierFlags: OptionSet {
        let rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        static let command = ModifierFlags(rawValue: 1 << 0)
        static let shift   = ModifierFlags(rawValue: 1 << 1)
        static let option  = ModifierFlags(rawValue: 1 << 2)
        static let control = ModifierFlags(rawValue: 1 << 3)
        static let none = ModifierFlags(rawValue: 0)
    }
}

#endif
