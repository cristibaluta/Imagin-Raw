//
//  IosDateSectionHeader.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 25.06.2026.
//

#if os(iOS)
import UIKit

final class IosDateSectionHeader: UICollectionReusableView {
    static let identifier = "IosDateSectionHeader"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabel
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.text = title
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 8, y: 0, width: bounds.width - 16, height: bounds.height)
    }
}
#endif
