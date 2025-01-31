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

import ProtonCore_Services

enum FeatureFlagKey: String, CaseIterable {
    case appRating = "RatingIOSMail"
    case sendRefactor = "SendMessageRefactor"
    case inAppFeedback = "InAppFeedbackIOS"
    case scheduleSend = "ScheduledSendFreemium"
    case senderImage = "ShowSenderImages"
    case referralPrompt = "ReferralActionSheetShouldBePresentedIOS"
}

// sourcery: mock
protocol FeatureFlagsSubscribeProtocol: AnyObject {
    func handleNewFeatureFlags(_ featureFlags: [String: Any])
}

// sourcery: mock
protocol FeatureFlagsDownloadServiceProtocol {
    func updateFeatureFlag(_ key: FeatureFlagKey, value: Any, completion: @escaping (Error?) -> Void)
}

/// This class is used to download the feature flags from the BE and send the flags to the subscribed objects.
class FeatureFlagsDownloadService: FeatureFlagsDownloadServiceProtocol {
    private let userID: UserID
    private let apiService: APIService
    private let sessionID: String
    private let subscribersTable: NSHashTable<AnyObject> = NSHashTable.weakObjects()
    var subscribers: [FeatureFlagsSubscribeProtocol] {
        subscribersTable.allObjects.compactMap { $0 as? FeatureFlagsSubscribeProtocol }
    }
    private(set) var lastFetchingTime: Date?
    private let appRatingStatusProvider: AppRatingStatusProvider
    private let sendRefactorStatusProvider: SendRefactorStatusProvider
    private let scheduleSendEnableStatusProvider: ScheduleSendEnableStatusProvider
    private let userIntroductionProgressProvider: UserIntroductionProgressProvider
    private let senderImageEnableStatusProvider: SenderImageStatusProvider
    private let referralPromptProvider: ReferralPromptProvider

    init(
        userID: UserID,
        apiService: APIService,
        sessionID: String,
        appRatingStatusProvider: AppRatingStatusProvider,
        sendRefactorStatusProvider: SendRefactorStatusProvider,
        scheduleSendEnableStatusProvider: ScheduleSendEnableStatusProvider,
        userIntroductionProgressProvider: UserIntroductionProgressProvider,
        senderImageEnableStatusProvider: SenderImageStatusProvider,
        referralPromptProvider: ReferralPromptProvider
    ) {
        self.userID = userID
        self.apiService = apiService
        self.sessionID = sessionID
        self.appRatingStatusProvider = appRatingStatusProvider
        self.sendRefactorStatusProvider = sendRefactorStatusProvider
        self.scheduleSendEnableStatusProvider = scheduleSendEnableStatusProvider
        self.userIntroductionProgressProvider = userIntroductionProgressProvider
        self.senderImageEnableStatusProvider = senderImageEnableStatusProvider
        self.referralPromptProvider = referralPromptProvider
    }

    func register(newSubscriber: FeatureFlagsSubscribeProtocol) {
        subscribersTable.add(newSubscriber)
    }

    enum FeatureFlagFetchingError: Error {
        case fetchingTooOften
        case selfIsReleased
    }

    func getFeatureFlags(completion: ((Error?) -> Void)?) {
        if let time = self.lastFetchingTime,
            Date().timeIntervalSince1970 - time.timeIntervalSince1970 > 300.0 {
            completion?(FeatureFlagFetchingError.fetchingTooOften)
            return
        }

        let request = FetchFeatureFlagsRequest()
        apiService.perform(request: request, response: FeatureFlagsResponse()) { [weak self] task, response in
            guard let self = self else {
                completion?(FeatureFlagFetchingError.selfIsReleased)
                return
            }
            if let error = task?.error {
                completion?(error)
                return
            }

            self.lastFetchingTime = Date()

            if !response.result.isEmpty {
                self.subscribers.forEach { $0.handleNewFeatureFlags(response.result) }
            }

            if let isScheduleSendEnabled = response.result[FeatureFlagKey.scheduleSend.rawValue] as? Bool {
                let stateBeforeTheUpdate = self.scheduleSendEnableStatusProvider.isScheduleSendEnabled(
                    userID: self.userID
                )

                self.scheduleSendEnableStatusProvider.setScheduleSendStatus(
                    enable: isScheduleSendEnabled,
                    userID: self.userID
                )

                switch stateBeforeTheUpdate {
                case .disabled where isScheduleSendEnabled:
                    // We need to reset spotlight when transitioning from expicitly disabled to enabled.
                    // However, we should not do it if the feature state was not set at all,
                    // which is the case right after sign in.
                    self.userIntroductionProgressProvider.markSpotlight(
                        for: .scheduledSend,
                        asSeen: false,
                        byUserWith: self.userID
                    )
                default:
                    break
                }
            } else {
                // If there is no SS feature flag, mark the feature as disabled, so that we'll be able to reset the
                // spotlight once the feature is enabled (wouldn't be possible if we left it as not set).
                self.scheduleSendEnableStatusProvider.setScheduleSendStatus(enable: false, userID: self.userID)
            }

            if let appRatingStatus = response.result[FeatureFlagKey.appRating.rawValue] as? Bool {
                self.appRatingStatusProvider.setIsAppRatingEnabled(appRatingStatus)
            }

            if let sendRefactor = response.result[FeatureFlagKey.sendRefactor.rawValue] as? Bool {
                self.sendRefactorStatusProvider.setIsSendRefactorEnabled(userID: self.userID, value: sendRefactor)
            }

            if let isSenderImageEnable = response.result[FeatureFlagKey.senderImage.rawValue] as? Bool {
                self.senderImageEnableStatusProvider.setIsSenderImageEnable(
                    enable: isSenderImageEnable,
                    userID: self.userID
                )
            }

            if let isReferralPromptAvailable = response.result[FeatureFlagKey.referralPrompt.rawValue] as? Bool {
                self.referralPromptProvider.setIsReferralPromptEnabled(
                    enabled: isReferralPromptAvailable,
                    userID: self.userID
                )
            }

            completion?(nil)
        }
    }

    func updateFeatureFlag(_ key: FeatureFlagKey, value: Any, completion: @escaping (Error?) -> Void) {
        let request = UpdateFeatureFlagsRequest(featureFlagName: key.rawValue, value: value)
        apiService.perform(
            request: request,
            callCompletionBlockUsing: .immediateExecutor
        ) { task, _ in
            completion(task?.error)
        }
    }

    #if DEBUG
    func setLastFetchedTime(date: Date) {
        self.lastFetchingTime = date
    }
    #endif
}
