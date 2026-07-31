//
//  GridType.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 31.07.2026.
//

import Foundation

enum GridType: String, CaseIterable, Identifiable {
    case small = "SmallGrid"
    case large = "LargeGrid"

    var id: String {
        rawValue
    }

    var columnCount: Int {
        self == .small ? 3 : 5
    }

    var thumbSize: CGFloat {
        self == .small ? 110 : 210
    }

    var cellHeight: CGFloat {
        self == .small ? 150 : 250
    }

    var displayName: String {
        self == .small ? "Small" : "Large"
    }

    var iconName: String {
        self == .small ? "square.grid.3x3" : "square.grid.4x4.fill"
    }
}
