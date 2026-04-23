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

/// NSSplitView subclass that returns a clear divider color
private final class TransparentDividerSplitView: NSSplitView {
    override var dividerColor: NSColor {
        return .clear
    }

    override var dividerThickness: CGFloat {
        return 0
    }
}
