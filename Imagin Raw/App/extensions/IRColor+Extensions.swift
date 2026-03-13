//
//  IRColor+Extensions.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 13.03.2026.
//

#if os(iOS)
import UIKit

// Colors available on macOS but not iOS
extension UIColor {
    static var windowBackgroundColor: UIColor {
        return .gray
    }
    static var controlBackgroundColor: UIColor {
        return .gray
    }
    static var textBackgroundColor: UIColor {
        return .systemBackground
    }
}
#endif
