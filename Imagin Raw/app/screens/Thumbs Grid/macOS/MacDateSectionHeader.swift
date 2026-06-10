//
//  MacDateSectionHeader.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05/06/2026.
//

#if os(macOS)
import AppKit

final class MacDateSectionHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("DateSectionHeader")

    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.stringValue = title
        label.sizeToFit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.frame = CGRect(x: 8,
                             y: (bounds.height - label.frame.height) / 2,
                             width: bounds.width - 16,
                             height: label.frame.height)
    }
}
#endif
