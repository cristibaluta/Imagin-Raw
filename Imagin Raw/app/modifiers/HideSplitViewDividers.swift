//
//  HideSplitViewDividers.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 23.04.2026.
//
import SwiftUI

// Removes the black divider lines between NavigationSplitView columns on macOS
// without using object_setClass (which causes KVO crashes with _NSSplitViewPartitionAdapter).
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
            // Zero out the divider thickness via the layout — safe, no class swap.
            // We hide the divider by zeroing its subview layer background directly.
            for subview in splitView.subviews {
                // AppKit renders dividers as thin subviews whose className contains "Divider"
                // or whose height/width == dividerThickness (usually 1pt).
                let isDivider = subview.className.lowercased().contains("divider")
                    || subview.frame.width <= 1
                    || subview.frame.height <= 1
                if isDivider {
                    subview.isHidden = true
                    subview.layer?.backgroundColor = CGColor.clear
                }
            }
            // Also zero out the drawn divider via the layer of the split view itself
            splitView.layer?.sublayers?.forEach { layer in
                if layer.frame.width <= 1 || layer.frame.height <= 1 {
                    layer.backgroundColor = CGColor.clear
                    layer.isHidden = true
                }
            }
        }

        // Hide the thin separator line at the top of each split pane
        if view.className.contains("TitlebarSeparator") || view.className.contains("Separator") {
            view.isHidden = true
        }

        for subview in view.subviews {
            walk(subview)
        }
    }
}
