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

protocol SettingsLocalStorageViewModelProtocol {
    var input: SettingsLocalStorageViewModelInput { get }
    var output: SettingsLocalStorageViewModelOutput { get }
}

protocol SettingsLocalStorageViewModelInput {
    func viewWillAppear()
    func didTapClearCachedData()
    func didTapClearAttachments()
    func didTapDownloadedMessages()
}

protocol SettingsLocalStorageViewModelOutput {
    var sections: [SettingsLocalStorageSection] { get }
    var searchIndexState: EncryptedSearchIndexState { get }
    var cachedDataStorage: Measurement<UnitInformationStorage> { get }
    var attachmentsStorage: Measurement<UnitInformationStorage> { get }
    var downloadedMessagesStorage: Measurement<UnitInformationStorage> { get }

    func setUIDelegate(_ delegate: SettingsLocalStorageUIProtocol)
}

protocol SettingsLocalStorageUIProtocol: AnyObject {
    func reloadData()
    func clearingCacheDidStart()
    func clearingCacheDidEnd(error: Error?)
}

enum SettingsLocalStorageSection: Int {
    case cachedData
    case attachments
    case downloadedMessages
}
