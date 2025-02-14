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

import ProtonCore_DataModel
import ProtonCore_Services
@testable import ProtonMail

extension UserManager {
    convenience init(
        api: APIService,
        role: UserInfo.OrganizationRole,
        userInfo: UserInfo = UserInfo.getDefault()
    ) {
        self.init(api: api, role: role, userInfo: userInfo, coreKeyMaker: MockKeyMakerProtocol())
    }

    convenience init(api: APIService, userID: String, coreKeyMaker: KeyMakerProtocol = MockKeyMakerProtocol()) {
        self.init(
            api: api,
            role: .none,
            userInfo: .init(
                maxSpace: nil,
                usedSpace: nil,
                language: nil,
                maxUpload: nil,
                role: nil,
                delinquent: nil,
                keys: nil,
                userId: userID,
                linkConfirmation: nil,
                credit: nil,
                currency: nil,
                subscribed: nil
            ),
            coreKeyMaker: coreKeyMaker
        )
    }
}
