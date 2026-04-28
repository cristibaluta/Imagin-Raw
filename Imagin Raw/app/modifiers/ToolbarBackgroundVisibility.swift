//
//  ToolbarBackgroundVisibility.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 23.04.2026.
//
import SwiftUI

struct ToolbarBackgroundVisibility: ViewModifier {
    var isHidden: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content
                .toolbarBackgroundVisibility(isHidden ? .hidden : .visible, for: .windowToolbar)
        } else {
            // Fallback for macOS 14 and earlier
            content
        }
        #elseif os(iOS)
        content
        #endif
    }
}
