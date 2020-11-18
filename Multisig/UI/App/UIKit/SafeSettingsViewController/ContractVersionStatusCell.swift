//
//  ContractVersionCell.swift
//  Multisig
//
//  Created by Andrey Scherbovich on 16.11.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class ContractVersionStatusCell: UITableViewCell {
    @IBOutlet private weak var identiconView: UIImageView!
    @IBOutlet private weak var headerLabel: UILabel!
    @IBOutlet private weak var statusView: UIImageView!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var detailLabel: UILabel!
    @IBOutlet private weak var button: UIButton!

    private var versionStatus: GnosisSafe.VersionStatus!

    var onViewDetails: (() -> Void)?

    static let rowHeight: CGFloat = 68

    @IBAction private func viewDetails() {
        onViewDetails?()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        headerLabel.setStyle(.headline)
        detailLabel.setStyle(GNOTextStyle.body.color(.gnoMediumGrey))
        addTarget(self, action: #selector(didTouchDown(sender:forEvent:)), for: .touchDown)
        addTarget(self, action: #selector(didTouchUp(sender:forEvent:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    func setAddress(_ value: Address) {
        identiconView.setAddress(value.hexadecimal)
        detailLabel.text = value.ellipsized()
        versionStatus = App.shared.gnosisSafe.version(implementation: value)

        let semiboldConfiguration = UIImage.SymbolConfiguration(weight: .semibold)

        switch versionStatus! {
        case .upToDate(let version):
            headerLabel.text = version
            statusView.image = UIImage(systemName: "checkmark", withConfiguration: semiboldConfiguration)
            statusView.tintColor = .gnoHold
            statusLabel.setStyle(GNOTextStyle.body.color(.gnoHold))
            statusLabel.text = "Up to date"

        case .upgradeAvailable(let version):
            headerLabel.text = version
            statusView.image = UIImage(systemName: "exclamationmark.circle", withConfiguration: semiboldConfiguration)
            statusView.tintColor = .gnoTomato
            statusLabel.setStyle(GNOTextStyle.body.color(.gnoTomato))
            statusLabel.text = "Upgrade available"

        case .unknown:
            headerLabel.text = "Unknown"
            statusView.image = nil
            statusLabel.text = nil
        }
    }

    func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {
        button.addTarget(target, action: action, for: controlEvents)
    }

    // visual reaction for user touches
    @objc private func didTouchDown(sender: UIButton, forEvent event: UIEvent) {
        alpha = 0.7
    }

    @objc private func didTouchUp(sender: UIButton, forEvent event: UIEvent) {
        alpha = 1.0
    }
}
