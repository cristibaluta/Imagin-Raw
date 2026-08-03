//
//  MacDuplicateSectionHeader.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 05/06/2026.
//
#if os(macOS)
import AppKit

final class MacDuplicateSectionHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("DuplicateSectionHeader")

    private let label      = NSTextField(labelWithString: "")
    private let pill       = NSView()
    private let actionBtn  = NSButton()
    private var groupIndex = 0
    private var onReview: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)

        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        pill.layer?.cornerRadius = 4
        addSubview(pill)

        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        pill.addSubview(label)

        actionBtn.bezelStyle = .rounded
        actionBtn.title = "Review"
        actionBtn.font = NSFont.systemFont(ofSize: 10)
        actionBtn.isBordered = false
        actionBtn.wantsLayer = true
        actionBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        actionBtn.layer?.cornerRadius = 3
        actionBtn.contentTintColor = .white
        actionBtn.target = self
        actionBtn.action = #selector(actionTapped)
        addSubview(actionBtn)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(title: String, index: Int, onReview: ((Int) -> Void)?) {
        self.groupIndex = index
        self.onReview = onReview
        label.stringValue = title
        label.sizeToFit()
        needsLayout = true
    }

    @objc private func actionTapped() {
        onReview?(groupIndex)
    }

    override func layout() {
        super.layout()

        let h: CGFloat = 20
        let hPad: CGFloat = 8
        let vPad: CGFloat = (bounds.height - h) / 2

        let pillW = label.frame.width + hPad * 2
        pill.frame = CGRect(x: 12, y: vPad, width: pillW, height: h)
        label.frame = CGRect(x: hPad,
                             y: (h - label.frame.height) / 2,
                             width: label.frame.width,
                             height: label.frame.height)

        let btnW: CGFloat = 50
        let btnH: CGFloat = 18
        actionBtn.frame = CGRect(x: pill.frame.maxX + 8,
                                 y: (bounds.height - btnH) / 2,
                                 width: btnW,
                                 height: btnH)

        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        pill.layer?.cornerRadius = 4

        actionBtn.layer?.backgroundColor = NSColor.systemBlue.cgColor
        actionBtn.layer?.cornerRadius = 3
    }
}
#endif
