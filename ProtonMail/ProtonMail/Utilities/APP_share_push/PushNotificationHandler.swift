// Copyright (c) 2021 Proton AG
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

import ProtonCore_Crypto
import UserNotifications

protocol EncryptionKitProvider {
    func encryptionKit(forSession uid: String) -> EncryptionKit?
}

extension PushNotificationDecryptor: EncryptionKitProvider {}

final class PushNotificationHandler {

    private enum PushManagementUnexpected: Error {
        case error(description: String)
    }

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestContent: UNMutableNotificationContent?

    private let dependencies: Dependencies

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    func handle(request: UNNotificationRequest, contentHandler: @escaping (UNNotificationContent) -> Void) {
        SystemLogger.log(message: #function, category: .pushNotification)

        bestContent = prepareForHandling(request: request, contentHandler: contentHandler)
        guard let bestContent = bestContent else { return }

        do {
            let payload = try pushNotificationPayload(userInfo: bestContent.userInfo)
            let uid = try uid(in: payload)
            bestContent.threadIdentifier = uid

            let encryptionKit = try encryptionKit(for: uid)
            let decryptedMessage = try decryptMessage(in: payload, encryptionKit: encryptionKit)
            let pushContent = try parseContent(with: decryptedMessage)

            populateNotification(content: bestContent, pushContent: pushContent)
            updateBadge(content: bestContent, payload: payload, pushData: pushContent.data, userId: uid)

        } catch let PushManagementUnexpected.error(message) {
            logPushNotificationError(message: message)

        } catch {
            logPushNotificationError(message: "unknown error handling push")

        }
        contentHandler(bestContent)
    }

    func willTerminate() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content
        // otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestContent = bestContent {
            contentHandler(bestContent)
        }
    }
}

// MARK: Private

private extension PushNotificationHandler {

    private func pushNotificationPayload(userInfo: [AnyHashable: Any]) throws -> PushNotificationPayload {
        do {
            return try PushNotificationPayload(userInfo: userInfo)
        } catch {
            let errorMessage = "Fail parsing push payload. Error: \(String(describing: error))"
            throw PushManagementUnexpected.error(description: errorMessage)
        }
    }

    private func uid(in payload: PushNotificationPayload) throws -> String {
        guard let uid = payload.uid else {
            throw PushManagementUnexpected.error(description: "uid not found in payload")
        }
        return uid
    }

    private func encryptionKit(for uid: String) throws -> EncryptionKit {
        guard let encryptionKit = dependencies.encryptionKitProvider.encryptionKit(forSession: uid) else {
            SharedUserDefaults().setNeedsToRegisterAgain(for: uid)
            throw PushManagementUnexpected.error(description: "no encryption kit for uid \(uid.redacted)")
        }
        return encryptionKit
    }

    private func decryptMessage(in payload: PushNotificationPayload, encryptionKit: EncryptionKit) throws -> String {
        guard let encryptedMessage = payload.encryptedMessage else {
            throw PushManagementUnexpected.error(description: "no encrypted message in payload")
        }

        let decryptionKey = DecryptionKey(
            privateKey: ArmoredKey(value: encryptionKit.privateKey),
            passphrase: Passphrase(value: encryptionKit.passphrase)
        )

        do {
            return try Decryptor.decrypt(
                decryptionKeys: [decryptionKey],
                encrypted: ArmoredMessage(value: encryptedMessage)
            )
        } catch {
            throw PushManagementUnexpected.error(description: "fail decrypting data")
        }
    }

    private func parseContent(with decryptedText: String) throws -> PushContent {
        do {
            return try PushContent(json: decryptedText)
        } catch {
            let redactedInfo = String(describing: error)
            throw PushManagementUnexpected.error(description: "fail parsing push content")
        }
    }

    private func prepareForHandling(
        request: UNNotificationRequest,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> (UNMutableNotificationContent?) {
        self.contentHandler = contentHandler
        guard let mutableContent = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
            return nil
        }
        mutableContent.body = "You received a new message!"
        mutableContent.sound = UNNotificationSound.default
        #if Enterprise
        mutableContent.title = "You received a new message!"
        #endif
        return mutableContent
    }

    private func populateNotification(content: UNMutableNotificationContent, pushContent: PushContent) {
        let pushData = pushContent.data
        content.title = pushData.sender.name.isEmpty ? pushData.sender.address : pushData.sender.name
        content.body = pushData.body

        // extra information to be used by notification actions
        content.userInfo["messageId"] = pushData.messageId
    }

    private func updateBadge(
        content: UNMutableNotificationContent,
        payload: PushNotificationPayload,
        pushData: PushData,
        userId: String
    ) {
        if dependencies.cacheStatus.primaryUserSessionId == userId {
            if payload.viewMode == 0, let unread = payload.unreadConversations { // conversation
                content.badge = NSNumber(value: unread)
            } else if payload.viewMode == 1, let unread = payload.unreadMessages { // single message
                content.badge = NSNumber(value: unread)
            } else if pushData.badge > 0 {
                content.badge = NSNumber(value: pushData.badge)
            } else {
                content.badge = nil
            }
        } else {
            content.badge = nil
        }
    }

    private func logPushNotificationError(message: String) {
        SystemLogger.log(message: message, category: .pushNotification, isError: true)
    }
}

extension PushNotificationHandler {
    struct Dependencies {
        let encryptionKitProvider: EncryptionKitProvider
        let cacheStatus: PushCacheStatus

        init(
            encryptionKitProvider: EncryptionKitProvider = PushNotificationDecryptor(),
            cacheStatus: PushCacheStatus = PushCacheStatus()
        ) {
            self.encryptionKitProvider = encryptionKitProvider
            self.cacheStatus = cacheStatus
        }
    }

    final class PushCacheStatus: SharedCacheBase {
        // swiftlint:disable nesting
        enum Key {
            static let primaryUserSessionId = "primary_user_session_id"
        }

        var primaryUserSessionId: String? {
            get {
                if getShared().object(forKey: Key.primaryUserSessionId) == nil {
                    return nil
                }
                return getShared().string(forKey: Key.primaryUserSessionId)
            }
            set {
                setValue(newValue, forKey: Key.primaryUserSessionId)
            }
        }
    }
}
