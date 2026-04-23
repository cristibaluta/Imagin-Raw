//
//  HideSplitViewDividers.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 23.04.2026.
//
import SwiftUI

// Removes the black divider lines between NavigationSplitView columns on macOS
// This is needed because on Tahoe there's an overlapping black line between the content and detail columns,
// covering also the toolbar
struct HideSplitViewDividers: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SplitViewDividerRemover())
    }
}

struct SplitViewDividerRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            Self.removeDividers(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.removeDividers(from: nsView)
        }
    }

    static func applyToKeyWindow() {
        guard let root = NSApp.keyWindow?.contentView else {
            return
        }
        walk(root)
    }

    private static func removeDividers(from view: NSView) {
        guard let root = view.window?.contentView else {
            return
        }
        walk(root)
    }

    private static func walk(_ view: NSView) {
        if let splitView = view as? NSSplitView {
            // Swap in a transparent-divider subclass
            object_setClass(splitView, TransparentDividerSplitView.self)
            splitView.dividerStyle = .thin
            // Hide any explicit divider subviews
            for subview in splitView.subviews {
                if subview.className.contains("Divider") || subview.className.contains("divider") {
                    subview.isHidden = true
                }
            }
        }
        // Hide the thin black separator line that sits at the top of each split pane
        // (className "NSTitlebarSeparatorView" or "NSThemeFrame" child with height == 1)
        if view.className.contains("TitlebarSeparator") || view.className.contains("Separator") {
            view.isHidden = true
        }
        for subview in view.subviews {
            walk(subview)
        }
    }
}

/// NSSplitView subclass that returns a clear, non-interactive divider
private final class TransparentDividerSplitView: NSSplitView {

    override var dividerColor: NSColor {
        return .clear
    }

    override var dividerThickness: CGFloat {
        return 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let all clicks pass through to subviews — never return self as the hit view
        // This prevents the divider from being draggable
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func resetCursorRects() {
        // No cursor rects — prevents the resize cursor from appearing on the divider
    }

    override func setPosition(_ position: CGFloat, ofDividerAt dividerIndex: Int) {
        // No-op — prevent any resize
    }
}
