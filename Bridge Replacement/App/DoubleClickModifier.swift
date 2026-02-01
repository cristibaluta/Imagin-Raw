//
//  DoubleClickModifier.swift
//  Bridge Replacement
//
//  Created by Cristian Baluta on 01.02.2026.
//

import SwiftUI
import AppKit

extension View {
    /// Adds a double click handler to this view (macOS only)
    ///
    /// Example
    /// ```
    /// Text("Hello")
    /// .onDoubleClick { print("Double click detected") }
    /// ```
    /// - Parameters:
    /// - handler: Block invoked when a double click is detected
    func onDoubleClick(handler: @escaping () -> Void) -> some View {
        modifier(DoubleClickHandler(handler: handler))
    }
}

struct DoubleClickHandler: ViewModifier {
    let handler: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            DoubleClickListeningViewRepresentable(handler: handler)
        }
    }
}

struct DoubleClickListeningViewRepresentable: NSViewRepresentable {
    let handler: () -> Void

    func makeNSView(context: Context) -> DoubleClickListeningView {
        DoubleClickListeningView(handler: handler)
    }

    func updateNSView(_ nsView: DoubleClickListeningView, context: Context) {}
}

class DoubleClickListeningView: NSView {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            handler()
        } else {
            // Pass single clicks to the superview so SwiftUI gestures can handle them
            super.mouseDown(with: event)
        }
    }
}
