//
//  PushNotificationServiceSubscription.swift
//  Proton Mail - Created on 08/11/2018.
//
//
//  Copyright (c) 2019 Proton AG
//
//  This file is part of Proton Mail.
//
//  Proton Mail is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Proton Mail is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Proton Mail.  If not, see <https://www.gnu.org/licenses/>.

import Foundation

protocol SubscriptionsPackProtocol {
    func encryptionKit(forUID uid: String) -> EncryptionKit?
}

extension PushNotificationService {
    enum SubscriptionState: String, Codable {
        case notReported, pending, reported
    }

    class SubscriptionsPack: SubscriptionsPackProtocol {
        private let subscriptionSaver: Saver<Set<SubscriptionWithSettings>>
        private let encryptionKitSaver: Saver<Set<SubscriptionSettings>>
        private let outdatedSaver: Saver<Set<SubscriptionSettings>>

        private(set) var subscriptions: Set<SubscriptionWithSettings> {
            get { return self.subscriptionSaver.get() ?? Set([])  }
            set {
                self.subscriptionSaver.set(newValue: newValue) // in keychain cuz should persist over reinstalls

                let reportedSettings: [SubscriptionSettings] = newValue
                    .compactMap { $0.state == .reported ? $0.settings : nil }
                self.encryptionKitSaver.set(newValue: Set(reportedSettings))
            }
        }

        private(set) var outdatedSettings: Set<SubscriptionSettings> {
            // cuz PushNotificationDecryptor can add values to this collection while app is running
            get { return self.outdatedSaver.get() ?? [] }
            set { self.outdatedSaver.set(newValue: newValue) } // in keychain cuz should persist over reinstalls
        }

        init(_ subSaver: Saver<Set<SubscriptionWithSettings>>,
             _ encSaver: Saver<Set<SubscriptionSettings>>,
             _ outSaver: Saver<Set<SubscriptionSettings>>) {
            self.subscriptionSaver = subSaver
            self.encryptionKitSaver = encSaver
            self.outdatedSaver = outSaver
        }

        func removed(_ settingsToRemove: SubscriptionSettings) {
            self.outdatedSettings.remove(settingsToRemove)
        }

        func outdate(_ settingsToMoveToOutdated: Set<SubscriptionSettings>) {
            outdatedSettings.formUnion(settingsToMoveToOutdated)
        }

        func insert(_ subscriptionsToInsert: Set<SubscriptionWithSettings>) {
            self.subscriptions.formUnion(subscriptionsToInsert)
        }

        func update(_ settings: SubscriptionSettings, toState: SubscriptionState) {
            let toReplace = self.subscriptions.filter { $0.settings == settings }
            var updated = self.subscriptions.subtracting(toReplace)

            updated.insert(.init(settings: settings, state: toState))
            self.subscriptions = updated
        }

        func removeFromActiveSubscriptions(_ settingsToRemove: Set<SubscriptionSettings>) {
            let toOutdate = subscriptions.filter { settingsToRemove.contains($0.settings) }
            subscriptions.subtract(toOutdate)
        }

        func settings() -> Set<SubscriptionSettings> {
            return Set(self.subscriptions.map { $0.settings })
        }

        func encryptionKit(forUID uid: String) -> EncryptionKit? {
            return self.encryptionKitSaver.get()?.first(where: { $0.UID == uid })?.encryptionKit
        }
    }

    class SubscriptionWithSettings: Hashable, Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            return "Settings: \(self.settings.token), \(self.settings.UID), \(self.settings.encryptionKit == nil ? "no encr kit" : "with encr ekit"), State: \(self.state.rawValue)"
        }

        var state: SubscriptionState
        private(set) var settings: SubscriptionSettings

        init(settings: SubscriptionSettings, state: SubscriptionState) {
            self.state = state
            self.settings = settings
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(self.settings)
        }

        static func == (
            lhs: PushNotificationService.SubscriptionWithSettings,
            rhs: PushNotificationService.SubscriptionWithSettings
        ) -> Bool {
            lhs.settings == rhs.settings
        }
    }
}
