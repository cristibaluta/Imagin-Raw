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

#elseif os(iOS)

import UIKit

typealias IRImage = UIImage
typealias IRSize = CGSize
typealias IRRect = CGRect

#endif
