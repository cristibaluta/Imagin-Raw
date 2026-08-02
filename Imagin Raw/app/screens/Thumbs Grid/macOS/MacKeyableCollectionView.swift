//
//  MacKeyableCollectionView.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 01.08.2026.
//

#if os(macOS)
import AppKit

final class MacKeyableCollectionView: NSCollectionView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
    // NSCollectionView handles Cmd+A via performKeyEquivalent (before keyDown),
    // which would update its internal selection model but bypass our viewModel.
    // Intercept it here and route through our handler instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
#endif
