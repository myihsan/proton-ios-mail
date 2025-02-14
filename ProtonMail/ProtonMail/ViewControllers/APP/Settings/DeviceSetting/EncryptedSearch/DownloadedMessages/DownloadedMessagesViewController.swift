// Copyright (c) 2023 Proton Technologies AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import Foundation
import ProtonCore_Foundations
import ProtonCore_UIFoundations
import UIKit

final class DownloadedMessagesViewController: UITableViewController, AccessibleView {
    private let viewModel: DownloadedMessagesViewModelProtocol

    private enum Layout {
        static let estimatedCellHeight: CGFloat = 48.0
        static let estimatedFooterHeight: CGFloat = 48.0
        static let firstSectionHeaderHeight: CGFloat = 32.0
        static let separationBetweenSections: CGFloat = 8.0
    }

    init(viewModel: DownloadedMessagesViewModelProtocol) {
        self.viewModel = viewModel
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
        viewModel.output.setUIDelegate(self)
    }

    private func setUpUI() {
        title = L11n.EncryptedSearch.downloaded_messages
        view.backgroundColor = ColorProvider.BackgroundSecondary
        view.frame = CGRect(origin: .zero, size: UIScreen.main.bounds.size)

        tableView.register(cellType: EncryptedSearchDownloadedMessagesCell.self)
        tableView.register(cellType: StorageLimitCell.self)
        tableView.register(cellType: LocalStorageCell.self)
        tableView.register(viewType: SettingsTextFooterView.self)

        tableView.estimatedSectionFooterHeight = Layout.estimatedFooterHeight
        tableView.estimatedRowHeight = Layout.estimatedCellHeight
        tableView.rowHeight = UITableView.automaticDimension
        tableView.allowsSelection = false
        tableView.delaysContentTouches = false
    }
}

// MARK: UITableViewDataSource

extension DownloadedMessagesViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.output.sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch viewModel.output.sections[indexPath.section] {
        case .messageHistory:
            return cellForMessageHistory()
        case .storageLimit:
            return cellForStorageLimitCell()
        case .localStorageUsed:
            return cellForLocalStorageUsed()
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch viewModel.output.sections[section] {
        case .messageHistory:
            return Layout.firstSectionHeaderHeight
        case .storageLimit, .localStorageUsed:
            return .leastNormalMagnitude
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return UIView()
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        switch viewModel.output.sections[section] {
        case .messageHistory, .storageLimit:
            return UIView()
        case .localStorageUsed:
            let footer = tableView.dequeue(viewType: SettingsTextFooterView.self)
            footer.set(text: L11n.EncryptedSearch.downloaded_messages_explanation)
            return footer
        }
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        switch viewModel.output.sections[section] {
        case .messageHistory, .storageLimit:
            return Layout.separationBetweenSections
        case .localStorageUsed:
            return UITableView.automaticDimension
        }
    }

    private func cellForMessageHistory() -> EncryptedSearchDownloadedMessagesCell {
        let cell = tableView.dequeue(cellType: EncryptedSearchDownloadedMessagesCell.self)
        let searchIndexState = viewModel.output.searchIndexState
        let cellInfo = searchIndexState.toDownloadedMessagesInfo(oldestMessageTime: viewModel.output.oldestMessageTime)
        cell.configure( info: cellInfo)
        return cell
    }

    private func cellForStorageLimitCell() -> StorageLimitCell {
        let bytes = Int(viewModel.output.storageLimitSelected.converted(to: .bytes).value)
        let cell = tableView.dequeue(cellType: StorageLimitCell.self)
        cell.delegate = self
        cell.configure(storageLimit: bytes)
        return cell
    }

    private func cellForLocalStorageUsed() -> LocalStorageCell {
        let cell = tableView.dequeue(cellType: LocalStorageCell.self)
        cell.delegate = self
        cell.configure(
            info: .init(
                title: LocalString._settings_title_of_storage_usage,
                message: nil,
                localStorageUsed: viewModel.output.localStorageUsed,
                isClearButtonHidden: false
            )
        )
        return cell
    }

    private func showDeleteMessagesAlert() {
        let alert = UIAlertController(
            title: L11n.EncryptedSearch.delete_messages_alert_title,
            message: L11n.EncryptedSearch.delete_messages_alert_message,
            preferredStyle: .alert
        )
        let enableTitle = LocalString._general_delete_action
        let cancelTitle = LocalString._general_cancel_button
        let enable = UIAlertAction(title: enableTitle, style: .destructive) { [weak self] _ in
            self?.viewModel.input.didTapClearStorageUsed()
        }
        let cancel = UIAlertAction(title: cancelTitle, style: .cancel)
        [enable, cancel].forEach(alert.addAction)
        present(alert, animated: true, completion: nil)
    }
}

extension DownloadedMessagesViewController: DownloadedMessagesUIProtocol {
    func reloadData() {
        tableView.reloadData()
    }
}

extension DownloadedMessagesViewController: StorageLimitCellDelegate {
    func didChangeStorageLimit(newLimit: Int) {
        let value = Measurement<UnitInformationStorage>(value: Double(newLimit), unit: .bytes)
        viewModel.input.didChangeStorageLimitValue(newValue: value)
    }
}

extension DownloadedMessagesViewController: LocalStorageCellDelegate {
    func didTapClear(sender: LocalStorageCell) {
        showDeleteMessagesAlert()
    }
}

private extension EncryptedSearchIndexState {

    func toDownloadedMessagesInfo(
        oldestMessageTime: String?
    ) -> EncryptedSearchDownloadedMessagesCell.DownloadedMessagesInfo {
        let oldestMessageInfo = oldestMessageTime ?? ""
        switch self {
        case .complete:
            return EncryptedSearchDownloadedMessagesCell.DownloadedMessagesInfo(
                icon: .success,
                title: .downlodedMessages,
                oldestMessage: .init(date: oldestMessageInfo, highlight: false),
                additionalInfo: .allMessagesDownloaded
            )
        case .partial:
            return .init(
                icon: .warning,
                title: .messageHistory,
                oldestMessage: .init(date: oldestMessageInfo, highlight: true),
                additionalInfo: .errorOutOfMemory
            )
        case .paused(let reason) where reason == .lowStorage:
            return .init(
                icon: .warning,
                title: .messageHistory,
                oldestMessage: .init(date: oldestMessageInfo, highlight: true),
                additionalInfo: .errorLowStorage
            )
        case .creatingIndex, .paused, .downloadingNewMessage, .background, .backgroundStopped:
            return .init(
                icon: .success,
                title: .messageHistory,
                oldestMessage: .init(date: oldestMessageInfo, highlight: false),
                additionalInfo: .downloadingInProgress
            )
        default:
            PMAssertionFailure("invalid state \(self)")
            // returning a dummy state
            return .init(
                icon: .warning,
                title: .messageHistory,
                oldestMessage: .init(date: nil, highlight: true),
                additionalInfo: .errorLowStorage
            )
        }
    }
}
