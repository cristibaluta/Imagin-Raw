//
//  IosDuplicateSectionHeader.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 25.06.2026.
//

#if os(iOS)
import UIKit

final class IosDuplicateSectionHeader: UICollectionReusableView {
    static let identifier = "IosDuplicateSectionHeader"

    private let pill      = UIView()
    private let label     = UILabel()
    private let reviewBtn = UIButton(type: .system)
    private var onReview: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        pill.layer.cornerRadius = 4
        addSubview(pill)
        label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        pill.addSubview(label)
        reviewBtn.setTitle("Review", for: .normal)
        reviewBtn.titleLabel?.font = UIFont.systemFont(ofSize: 10)
        reviewBtn.backgroundColor = UIColor.systemBlue
        reviewBtn.layer.cornerRadius = 3
        reviewBtn.setTitleColor(.white, for: .normal)
        reviewBtn.addTarget(self, action: #selector(reviewTapped), for: .touchUpInside)
        addSubview(reviewBtn)
    }
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(group: DuplicateGroup, index: Int, onReview: (() -> Void)?) {
        self.onReview = onReview
        let pct = max(0, min(100, Int(((1.0 - Double(group.distance)) * 100).rounded())))
        label.text = "Group \(index + 1)  ·  \(pct)% similarity"
        label.sizeToFit()
        setNeedsLayout()
    }

    @objc private func reviewTapped() {
        onReview?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let pillH: CGFloat = 20
        let hPad: CGFloat = 8
        let pillW = label.intrinsicContentSize.width + hPad * 2
        pill.frame = CGRect(x: 12, y: (h - pillH) / 2, width: pillW, height: pillH)
        label.frame = CGRect(x: hPad,
                             y: (pillH - label.intrinsicContentSize.height) / 2,
                             width: label.intrinsicContentSize.width,
                             height: label.intrinsicContentSize.height)
        let btnW: CGFloat = 60, btnH: CGFloat = 22
        reviewBtn.frame = CGRect(x: pill.frame.maxX + 8, y: (h - btnH) / 2, width: btnW, height: btnH)
    }
}
#endif
