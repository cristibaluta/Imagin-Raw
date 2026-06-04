//
//  Date+Extensions.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 04.06.2026.
//

import Foundation

extension Date {

    private static let EEEEMMMdyyyyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"  // e.g. "Monday, Sept 12, 2025"
        return f
    }()

    /// Returns the date formatted as "EEEE, MMM d, yyyy" — e.g. "Monday, Sept 12, 2025"
    var EEEEMMMdyyyy: String {
        Date.EEEEMMMdyyyyFormatter.string(from: self)
    }
}
