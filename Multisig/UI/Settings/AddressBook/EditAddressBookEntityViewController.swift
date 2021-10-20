//
//  EditAddressBookEntityViewController.swift
//  Multisig
//
//  Created by Moaaz on 10/20/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class EditAddressBookEntityViewController: UIViewController {

    // if not nil, then back button replaced with 'Done' button
    private var completion: (() -> Void)?

    private var entity: AddressBookEntity!
    let tableBackgroundColor: UIColor = .primaryBackground

    convenience init(entity: AddressBookEntity, completion: (() -> Void)? = nil) {
        self.init()
        self.entity = entity
        self.completion = completion
    }

    override func loadView() {
        super.loadView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        assert(keyInfo != nil, "Developer error: expect to have an entity")

        navigationItem.title = "Address book entity"

        if completion != nil {
            let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(pop))
            navigationItem.rightBarButtonItem = doneButton
        }

        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = tableBackgroundColor
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68

        tableView.registerCell(BasicCell.self)
        tableView.registerCell(DetailAccountCell.self)
        tableView.registerCell(KeyTypeTableViewCell.self)
        tableView.registerCell(RemoveCell.self)
        tableView.registerCell(SwitchTableViewCell.self)
        tableView.registerHeaderFooterView(BasicHeaderView.self)

        sections = [
            (section: .name("OWNER NAME"), items: [Section.Name.name]),

            (section: .keyAddress("OWNER ADDRESS"),
             items: [Section.KeyAddress.address]),

            (section: .ownerKeyType("OWNER TYPE"),
             items: [Section.OwnerKeyType.type])]

        if keyInfo.keyType == .walletConnect {
            sections.append((section: .connected("WC CONNECTION"), items: [Section.Connected.connected]))
        }

        sections.append((section: .advanced, items: [Section.Advanced.remove]))

        for notification in [Notification.Name.ownerKeyUpdated, .wcDidDisconnectClient] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reloadData),
                name: notification,
                object: nil)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(walletConnectSessionCreated(_:)),
            name: .wcDidConnectClient,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pop),
            name: .ownerKeyRemoved,
            object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.ownerKeyDetails)
    }

    @IBAction func removeButtonTouched(_ sender: Any) {
        removeKey()
    }

    @objc private func didTapExportButton() {
        let exportViewController = ExportViewController()

        do {
            if let privateKey = try keyInfo.privateKey() {
                exportViewController.privateKey = privateKey.keyData.toHexStringWithPrefix()
                exportViewController.seedPhrase = privateKey.mnemonic.map { $0.split(separator: " ").map(String.init) }
            } else {
                App.shared.snackbar.show(error: GSError.PrivateKeyDataNotFound(reason: "Key data does not exist"))
                return
            }
        } catch {
            App.shared.snackbar.show(error: GSError.PrivateKeyFetchError(reason: error.localizedDescription))
            return
        }

        if App.shared.auth.isPasscodeSet && AppSettings.passcodeOptions.contains(.useForExportingKeys) {
            let vc = EnterPasscodeViewController()
            vc.passcodeCompletion = { [weak self] success in
                guard let `self` = self else { return }
                self.dismiss(animated: true) {
                    if success {
                        self.show(exportViewController, sender: self)
                    }
                }
            }

            present(vc, animated: true, completion: nil)
        } else {
            show(exportViewController, sender: self)
        }
    }

    @objc private func reloadData() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    @objc private func pop() {
        navigationController?.popViewController(animated: true)
        completion?()
    }

    private func removeKey() {
        let alertController = UIAlertController(
            title: nil,
            message: "Removing the owner key only removes it from this app. It doesn’t delete any Safes from this app or from blockchain. Transactions for Safes controlled by this key will no longer be available for signing in this app.",
            preferredStyle: .actionSheet)
        let remove = UIAlertAction(title: "Remove", style: .destructive) { _ in
            OwnerKeyController.remove(keyInfo: self.keyInfo)
        }
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(remove)
        alertController.addAction(cancel)
        present(alertController, animated: true)
    }

    private func reconnectKey() {
        assert(keyInfo.keyType == .walletConnect, "Developer error: worng key type used")

        if let installedWallet = keyInfo.installedWallet {
            guard let topic = WalletConnectClientController.reconnectWithInstalledWallet(installedWallet) else { return }
            walletPerTopic[topic] = installedWallet
            waitingForSession = true
        } else {
            showConnectionQRCodeController()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]
        switch item {
        case Section.Name.name:
            return tableView.basicCell(name: keyInfo.name ?? "", indexPath: indexPath)
        case Section.KeyAddress.address:
            return addressDetailsCell(address: keyInfo.address, showQRCode: true, indexPath: indexPath)
        case Section.OwnerKeyType.type:
            return keyTypeCell(type: keyInfo.keyType, indexPath: indexPath)
        case Section.Connected.connected:
            return switchCell(for: indexPath, with: "Connected", isOn: WalletConnectClientController.shared.isConnected(keyInfo: keyInfo))
        case Section.Advanced.remove:
            return removeKeyCell(indexPath: indexPath)
        default:
            return UITableViewCell()
        }
    }

    private func addressDetailsCell(address: Address, showQRCode: Bool, indexPath: IndexPath, badgeName: String? = nil) -> UITableViewCell {
        let cell = tableView.dequeueCell(DetailAccountCell.self, for: indexPath)
        cell.setAccount(address: address, badgeName: badgeName, showQRCode: true)
        return cell
    }

    private func keyTypeCell(type: KeyType, indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(KeyTypeTableViewCell.self, for: indexPath)
        cell.set(name: type.name, iconName: type.imageName)
        cell.selectionStyle = .none
        return cell
    }

    private func removeKeyCell(indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(RemoveCell.self, for: indexPath)
        cell.set(title: "Remove owner key")
        cell.onRemove = { [weak self] in
            self?.removeKey()
        }
        cell.selectionStyle = .none
        return cell
    }

    func switchCell(for indexPath: IndexPath, with text: String, isOn: Bool) -> SwitchTableViewCell {
        let cell = tableView.dequeueCell(SwitchTableViewCell.self, for: indexPath)
        cell.setText(text)
        cell.setOn(isOn, animated: false)
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        switch item {
        case Section.Name.name:
            let vc = EditOwnerKeyViewController(keyInfo: keyInfo)
            show(vc, sender: self)
        case Section.Connected.connected:
            if WalletConnectClientController.shared.isConnected(keyInfo: keyInfo) {
                WalletConnectClientController.shared.disconnect()
            } else {
                // try to reconnect
                if let installedWallet = keyInfo.installedWallet {
                    self.reconnectWithInstalledWallet(installedWallet)
                } else {
                    self.showConnectionQRCodeController()
                }
            }
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let item = sections[indexPath.section].items[indexPath.row]
        switch item {
        case Section.KeyAddress.address:
            return UITableView.automaticDimension

        case Section.Advanced.remove:
            return RemoveCell.rowHeight

        default:
            return BasicCell.rowHeight
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection _section: Int) -> UIView? {
        let section = sections[_section].section
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        switch section {
        case Section.name(let name):
            view.setName(name)
        case Section.keyAddress(let name):
            view.setName(name)
        case Section.ownerKeyType(let name):
            view.setName(name)
        case Section.connected(let name):
            view.setName(name)
        case Section.advanced:
            break
        }

        return view
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection _section: Int) -> CGFloat {
        let section = sections[_section].section
        if case Section.advanced = section {
            return 0
        }

        return BasicHeaderView.headerHeight
    }
}
