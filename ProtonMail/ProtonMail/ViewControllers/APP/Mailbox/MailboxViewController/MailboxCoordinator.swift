//
//  MailboxCoordinator.swift.swift
//  Proton Mail - Created on 12/10/18.
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

import class ProtonCore_DataModel.UserInfo
import ProtonCore_TroubleShooting
import ProtonMailAnalytics
import SideMenuSwift

// sourcery: mock
protocol MailboxCoordinatorProtocol: AnyObject {
    var pendingActionAfterDismissal: (() -> Void)? { get set }
    var conversationCoordinator: ConversationCoordinator? { get }
    var singleMessageCoordinator: SingleMessageCoordinator? { get }

    func go(to dest: MailboxCoordinator.Destination, sender: Any?)
    func presentToolbarCustomizationView(
        allActions: [MessageViewActionSheetAction],
        currentActions: [MessageViewActionSheetAction]
    )
}

class MailboxCoordinator: MailboxCoordinatorProtocol, CoordinatorDismissalObserver {
    let viewModel: MailboxViewModel
    var services: ServiceFactory
    private let contextProvider: CoreDataContextProviderProtocol
    private let internetStatusProvider: InternetConnectionStatusProvider

    weak var viewController: MailboxViewController?
    private(set) weak var navigation: UINavigationController?
    private weak var sideMenu: SideMenuController?
    var pendingActionAfterDismissal: (() -> Void)?
    private(set) var singleMessageCoordinator: SingleMessageCoordinator?
    private(set) var conversationCoordinator: ConversationCoordinator?
    private let getApplicationState: () -> UIApplication.State
    let infoBubbleViewStatusProvider: ToolbarCustomizationInfoBubbleViewStatusProvider
    private var timeOfLastNavigationToMessageDetails: Date?

    private let troubleShootingHelper = TroubleShootingHelper(doh: BackendConfiguration.shared.doh)
    private let composeViewModelFactory: ComposeViewModelDependenciesFactory

    init(sideMenu: SideMenuController?,
         nav: UINavigationController?,
         viewController: MailboxViewController,
         viewModel: MailboxViewModel,
         services: ServiceFactory,
         contextProvider: CoreDataContextProviderProtocol,
         infoBubbleViewStatusProvider: ToolbarCustomizationInfoBubbleViewStatusProvider,
         internetStatusProvider: InternetConnectionStatusProvider = InternetConnectionStatusProvider(),
         getApplicationState: @escaping () -> UIApplication.State = {
        return UIApplication.shared.applicationState
    }
    ) {
        self.sideMenu = sideMenu
        self.navigation = nav
        self.viewController = viewController
        self.viewModel = viewModel
        self.services = services
        self.contextProvider = contextProvider
        self.internetStatusProvider = internetStatusProvider
        self.getApplicationState = getApplicationState
        self.infoBubbleViewStatusProvider = infoBubbleViewStatusProvider
        self.composeViewModelFactory = services.makeComposeViewModelDependenciesFactory()
    }

    enum Destination: String {
        case composer = "toCompose"
        case composeShow = "toComposeShow"
        case composeMailto = "toComposeMailto"
        case composeScheduledMessage = "composeScheduledMessage"
        case search = "toSearchViewController"
        case details = "SingleMessageViewController"
        case onboardingForNew = "to_onboardingForNew_segue"
        case onboardingForUpdate = "to_onboardingForUpdate_segue"
        case troubleShoot = "toTroubleShootSegue"
        case newFolder = "toNewFolder"
        case newLabel = "toNewLabel"
        case referAFriend = "referAFriend"

        init?(rawValue: String) {
            switch rawValue {
            case "toCompose":
                self = .composer
            case "toComposeShow", String(describing: ComposeContainerViewController.self):
                self = .composeShow
            case "toComposeMailto":
                self = .composeMailto
            case "toSearchViewController", String(describing: SearchViewController.self):
                self = .search
            case "toMessageDetailViewController",
                String(describing: SingleMessageViewController.self),
                String(describing: ConversationViewController.self):
                self = .details
            case "to_onboardingForNew_segue":
                self = .onboardingForNew
            case "to_onboardingForUpdate_segue":
                self = .onboardingForUpdate
            case "toTroubleShootSegue":
                self = .troubleShoot
            case "composeScheduledMessage":
                self = .composeScheduledMessage
            case "referAFriend":
                self = .referAFriend
            default:
                return nil
            }
        }
    }

    /// if called from a segue prepare don't call push again
    func start() {
        viewController?.set(viewModel: viewModel)
        self.viewController?.set(coordinator: self)

        if let navigation = self.navigation, self.sideMenu != nil {
            self.sideMenu?.setContentViewController(to: navigation)
            self.sideMenu?.hideMenu()
        }
        if let presented = self.viewController?.presentedViewController {
            presented.dismiss(animated: false, completion: nil)
        }
    }

    func go(to dest: Destination, sender: Any? = nil) {
        switch dest {
        case .details:
            handleDetailDirectFromMailBox()
        case .newFolder:
            self.presentCreateFolder(type: .folder)
        case .newLabel:
            presentCreateFolder(type: .label)
        case .onboardingForNew:
            presentOnboardingView()
        case .onboardingForUpdate:
            presentNewBrandingView()
        case .composer:
            navigateToComposer(existingMessage: nil)
        case .composeShow, .composeMailto:
            self.viewController?.cancelButtonTapped()

            guard let message = sender as? Message else { return }

            navigateToComposer(existingMessage: message)
        case .composeScheduledMessage:
            guard let message = sender as? Message else { return }
            editScheduleMsg(messageID: MessageID(message.messageID), originalScheduledTime: nil)
        case .troubleShoot:
            presentTroubleShootView()
        case .search:
            presentSearch()
        case .referAFriend:
            presentReferAFriend()
        }
    }

    func follow(_ deeplink: DeepLink) {
        guard let path = deeplink.popFirst, let dest = Destination(rawValue: path.name) else { return }

        switch dest {
        case .details:
            handleDetailDirectFromNotification(node: path)
            viewModel.resetNotificationMessage()
        case .composeShow:
            if let nav = self.navigation {
                let user = self.viewModel.user

                let existingMessage: Message?
                if let messageID = path.value {
                    existingMessage = user.messageService.fetchMessages(
                        withIDs: [messageID],
                        in: contextProvider.mainContext
                    ).first
                } else {
                    existingMessage = nil
                }

                let viewModel = ComposeViewModel(
                    msg: existingMessage,
                    action: existingMessage == nil ? .newDraft : .openDraft,
                    msgService: user.messageService,
                    user: user,
                    dependencies: composeViewModelFactory.makeViewModelDependencies(user: user)
                )
                showComposer(viewModel: viewModel, navigationVC: nav)
            }
        case .composeMailto where path.value != nil:
            followToComposeMailTo(path: path.value, deeplink: deeplink)
        case .composeScheduledMessage where path.value != nil:
            guard let messageID = path.value,
                  // TODO: do we need this check?
                  path.states?["originalScheduledTime"] as? Date != nil else {
                return
            }
            let user = self.viewModel.user
            let msgService = user.messageService
            if let message = msgService.fetchMessages(withIDs: [messageID], in: contextProvider.mainContext).first {
                navigateToComposer(
                    existingMessage: message,
                    isEditingScheduleMsg: true
                )
            }
        default:
            self.go(to: dest, sender: deeplink)
        }
    }
}

extension MailboxCoordinator {
    private func showComposer(viewModel: ComposeViewModel, navigationVC: UINavigationController) {
        let composer = ComposerViewFactory.makeComposer(
            childViewModel: viewModel,
            contextProvider: contextProvider,
            userIntroductionProgressProvider: userCachedStatus,
            scheduleSendEnableStatusProvider: userCachedStatus)
        navigationVC.present(composer, animated: true)
    }

    private func presentCreateFolder(type: PMLabelType) {
        let user = self.viewModel.user
        let folderLabels = user.labelService.getMenuFolderLabels()
        let dependencies = LabelEditViewModel.Dependencies(userManager: user)
        let labelEditNavigationController = LabelEditStackBuilder.make(
            editMode: .creation,
            type: type,
            labels: folderLabels,
            dependencies: dependencies,
            coordinatorDismissalObserver: self
        )
        viewController?.navigationController?.present(labelEditNavigationController, animated: true, completion: nil)
    }

    private func presentOnboardingView() {
        let viewController = OnboardViewController()
        viewController.modalPresentationStyle = .fullScreen
        self.viewController?.present(viewController, animated: true, completion: nil)
    }

    private func presentNewBrandingView() {
        let viewController = NewBrandingViewController.instance()
        viewController.modalPresentationStyle = .overCurrentContext
        self.viewController?.present(viewController, animated: true, completion: nil)
    }

    private func navigateToComposer(
        existingMessage: Message?,
        isEditingScheduleMsg: Bool = false) {
        guard let navigationVC = navigation else {
            return
        }
        let composer = ComposerViewFactory.makeComposer(
            msg: existingMessage,
            action: existingMessage == nil ? .newDraft : .openDraft,
            user: viewModel.user,
            contextProvider: contextProvider,
            isEditingScheduleMsg: isEditingScheduleMsg,
            userIntroductionProgressProvider: userCachedStatus,
            scheduleSendEnableStatusProvider: userCachedStatus,
            internetStatusProvider: internetStatusProvider,
            coreKeyMaker: services.get()
        )
        navigationVC.present(composer, animated: true)
    }

    private func presentSearch() {
        let coreDataService = services.get(by: CoreDataService.self)
        // TODO: get shared ES service.
        let esService = EncryptedSearchService()
        let viewModel = SearchViewModel(
            serviceFactory: services,
            user: viewModel.user,
            coreDataContextProvider: coreDataService,
            internetStatusProvider: services.get(),
            dependencies: .init(
                coreKeyMaker: services.get(),
                fetchMessageDetail: FetchMessageDetail(
                    dependencies: .init(
                        queueManager: services.get(by: QueueManager.self),
                        apiService: viewModel.user.apiService,
                        contextProvider: coreDataService,
                        cacheService: viewModel.user.cacheService
                    )
                ),
                fetchSenderImage: FetchSenderImage(
                    dependencies: .init(
                        senderImageService: .init(
                            dependencies: .init(
                                apiService: viewModel.user.apiService,
                                internetStatusProvider: internetStatusProvider
                            )
                        ),
                        senderImageStatusProvider: userCachedStatus,
                        mailSettings: viewModel.user.mailSettings
                    )
                ), messageSearch: MessageSearch(
                    dependencies: .init(
                        isESEnable: UserInfo.isEncryptedSearchEnabled,
                        esDefaultCache: EncryptedSearchUserDefaultCache(),
                        userID: viewModel.user.userID,
                        backendSearch: BackendSearch(
                            dependencies: .init(
                                apiService: viewModel.user.apiService,
                                contextProvider: coreDataService,
                                userID: viewModel.user.userID
                            )
                        ),
                        encryptedSearch: EncryptedSearch(
                            dependencies: .init(
                                encryptedSearchService: esService,
                                contextProvider: coreDataService,
                                userID: viewModel.user.userID,
                                fetchMessageMetaData: FetchMessageMetaData(
                                    params: .init(userID: viewModel.user.userID.rawValue),
                                    dependencies: .init(
                                        messageDataService: viewModel.user.messageService,
                                        contextProvider: coreDataService
                                    )
                                ),
                                messageDataService: viewModel.user.messageService
                            )
                        ), esStateProvider: esService
                    )
                )
            )
        )
        let viewController = SearchViewController(viewModel: viewModel, serviceFactory: services)
        viewModel.uiDelegate = viewController
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalTransitionStyle = .coverVertical
        navigationController.modalPresentationStyle = .fullScreen
        self.viewController?.present(navigationController, animated: true)
    }

    func fetchConversationFromBEIfNeeded(conversationID: ConversationID, goToDetailPage: @escaping () -> Void) {
        guard internetStatusProvider.currentStatus != .notConnected else {
            goToDetailPage()
            return
        }

        viewController?.showProgressHud()
        viewModel.fetchConversationDetail(conversationID: conversationID) { [weak self] in
            defer {
                self?.viewController?.hideProgressHud()
            }
            // Prevent the app tries to push a new view when the app enters
            // the background due to long network fetching time.
            // It could cause the app crashed in the background.
            if self?.getApplicationState() == .background {
                return
            }
            goToDetailPage()
        }
    }

    private func followToComposeMailTo(path: String?, deeplink: DeepLink) {
        if let msgID = path,
           let existingMsg = Message.messageForMessageID(msgID, inManagedObjectContext: contextProvider.mainContext) {
            navigateToComposer(existingMessage: existingMsg)
            return
        }

        if let nav = self.navigation,
           let value = path,
           let mailToURL = URL(string: value) {
            let user = self.viewModel.user
            let composer = ComposerViewFactory.makeComposer(
                msg: nil,
                action: .newDraft,
                user: user,
                contextProvider: contextProvider,
                isEditingScheduleMsg: false,
                userIntroductionProgressProvider: userCachedStatus,
                scheduleSendEnableStatusProvider: userCachedStatus,
                internetStatusProvider: internetStatusProvider,
                coreKeyMaker: services.get(),
                mailToUrl: mailToURL
            )
            nav.present(composer, animated: true)
        }
    }

    private func presentTroubleShootView() {
        if let viewController = viewController {
            troubleShootingHelper.showTroubleShooting(over: viewController)
        }
    }

    func presentToolbarCustomizationView(
        allActions: [MessageViewActionSheetAction],
        currentActions: [MessageViewActionSheetAction]
    ) {
        let view = ToolbarCustomizeViewController<MessageViewActionSheetAction>(
            viewModel: .init(
                currentActions: currentActions,
                allActions: allActions,
                actionsNotAddableToToolbar: MessageViewActionSheetAction.actionsNotAddableToToolbar,
                defaultActions: MessageViewActionSheetAction.defaultActions,
                infoBubbleViewStatusProvider: infoBubbleViewStatusProvider
            )
        )
        view.customizationIsDone = { [weak self] result in
            self?.viewController?.showProgressHud()
            self?.viewModel.updateToolbarActions(
                actions: result,
                completion: { error in
                    if let error = error {
                        error.alertErrorToast()
                    }
                    self?.viewController?.refreshActionBarItems()
                    self?.viewController?.hideProgressHud()
                })
        }
        let nav = UINavigationController(rootViewController: view)
        viewController?.navigationController?.present(nav, animated: true)
    }

    private func editScheduleMsg(messageID: MessageID, originalScheduledTime: OriginalScheduleDate?) {
        let context = contextProvider.mainContext
        guard let msg = Message.messageForMessageID(messageID.rawValue, inManagedObjectContext: context) else {
            return
        }
        navigateToComposer(
            existingMessage: msg,
            isEditingScheduleMsg: true
        )
    }
}

extension MailboxCoordinator {
    private func handleDetailDirectFromMailBox() {
        switch viewModel.locationViewMode {
        case .singleMessage:
            messageToShow(isNotification: false, node: nil) { [weak self] message in
                guard let message = message else { return }
                if UserInfo.isConversationSwipeEnabled {
                    self?.presentPageViewsFor(message: message)
                } else {
                    self?.present(message: message)
                }
            }
        case .conversation:
            conversationToShow(isNotification: false, message: nil) { [weak self] conversation in
                guard let conversation = conversation else { return }
                if UserInfo.isConversationSwipeEnabled {
                    self?.presentPageViewsFor(conversation: conversation, targetID: nil)
                } else {
                    self?.present(conversation: conversation, targetID: nil)
                }
            }
        }
    }

    private func handleDetailDirectFromNotification(node: DeepLink.Node) {
        if
            let timeOfLastNavigationToMessageDetails,
            Date().timeIntervalSince(timeOfLastNavigationToMessageDetails) < 3
        {
            return
        }

        timeOfLastNavigationToMessageDetails = Date()

        resetNavigationViewControllersIfNeeded()
        presentMessagePlaceholderIfNeeded()

        messageToShow(isNotification: true, node: node) { [weak self] message in
            guard let self = self,
                  let message = message else {
                self?.viewController?.navigationController?.popViewController(animated: true)
                L11n.Error.cant_open_message.alertToastBottom()
                return
            }
            let messageID = message.messageID
            switch self.viewModel.locationViewMode {
            case .singleMessage:
                if UserInfo.isConversationSwipeEnabled {
                    self.presentPageViewsFor(message: message)
                } else {
                    self.present(message: message)
                }
            case .conversation:
                self.conversationToShow(isNotification: true, message: message) { [weak self] conversation in
                    guard let conversation = conversation else {
                        self?.viewController?.navigationController?.popViewController(animated: true)
                        L11n.Error.cant_open_message.alertToastBottom()
                        return
                    }

                    if UserInfo.isConversationSwipeEnabled {
                        self?.presentPageViewsFor(conversation: conversation, targetID: messageID)
                    } else {
                        self?.present(conversation: conversation, targetID: messageID)
                    }
                }
            }
        }
    }

    private func conversationToShow(
        isNotification: Bool,
        message: MessageEntity?,
        completion: @escaping (ConversationEntity?) -> Void
    ) {
        guard isNotification else {
            // Click from mailbox list
            guard let indexPathForSelectedRow = viewController?.tableView.indexPathForSelectedRow,
                  let conversation = viewModel.itemOfConversation(index: indexPathForSelectedRow) else {
                completion(nil)
                return
            }
            completion(conversation)
            return
        }

        // From notification
        guard let conversationID = message?.conversationID else {
            completion(nil)
            return
        }
        fetchConversationFromBEIfNeeded(conversationID: conversationID) { [weak self] in
            guard
                let context = self?.contextProvider.mainContext,
                let conversation = Conversation
                    .conversationForConversationID(
                        conversationID.rawValue,
                        inManagedObjectContext: context
                    )
            else {
                completion(nil)
                return
            }
            completion(ConversationEntity(conversation))
        }
    }

    private func messageToShow(
        isNotification: Bool,
        node: DeepLink.Node?,
        completion: @escaping (MessageEntity?) -> Void
    ) {
        guard isNotification else {
            // Click from mailbox list
            guard let indexPathForSelectedRow = viewController?.tableView.indexPathForSelectedRow,
                  let message = self.viewModel.item(index: indexPathForSelectedRow) else {
                completion(nil)
                return
            }
            completion(message)
            return
        }

        // From notification
        guard let messageID = node?.value else {
            completion(nil)
            return
        }
        viewModel.user.messageService.fetchNotificationMessageDetail(MessageID(messageID)) { result in
            switch result {
            case .success(let message):
                completion(message)
            case .failure(let error):
                SystemLogger.log(message: "\(error)", isError: true)
                completion(nil)
            }
        }
    }

    private func present(message: MessageEntity) {
        guard let navigationController = viewController?.navigationController else { return }
        let coordinator = SingleMessageCoordinator(
            serviceFactory: services,
            navigationController: navigationController,
            labelId: viewModel.labelID,
            message: message,
            user: viewModel.user,
            infoBubbleViewStatusProvider: infoBubbleViewStatusProvider
        )
        coordinator.goToDraft = { [weak self] msgID, originalScheduleTime in
            self?.editScheduleMsg(messageID: msgID, originalScheduledTime: originalScheduleTime)
        }
        singleMessageCoordinator = coordinator
        coordinator.start()
    }

    private func present(conversation: ConversationEntity, targetID: MessageID?) {
        guard let navigationController = viewController?.navigationController else { return }
        let coordinator = ConversationCoordinator(
            labelId: viewModel.labelID,
            navigationController: navigationController,
            conversation: conversation,
            user: viewModel.user,
            internetStatusProvider: services.get(by: InternetConnectionStatusProvider.self),
            infoBubbleViewStatusProvider: infoBubbleViewStatusProvider,
            contextProvider: contextProvider,
            targetID: targetID,
            serviceFactory: services
        )
        conversationCoordinator = coordinator
        coordinator.goToDraft = { [weak self] msgID, originalScheduledTime in
            self?.editScheduleMsg(messageID: msgID, originalScheduledTime: originalScheduledTime)
        }
        coordinator.start()
    }

    private func presentPageViewsFor(message: MessageEntity) {
        let pageVM = MessagePagesViewModel(
            initialID: message.messageID,
            isUnread: viewController?.isShowingUnreadMessageOnly ?? false,
            labelID: viewModel.labelID,
            user: viewModel.user,
            userIntroduction: userCachedStatus,
            infoBubbleViewStatusProvider: infoBubbleViewStatusProvider,
            goToDraft: { [weak self] msgID, originalScheduledTime in
                self?.editScheduleMsg(messageID: msgID, originalScheduledTime: originalScheduledTime)
            }
        )
        presentPageViews(pageVM: pageVM)
    }

    private func presentPageViewsFor(conversation: ConversationEntity, targetID: MessageID?) {
        let pageVM = ConversationPagesViewModel(
            initialID: conversation.conversationID,
            isUnread: viewController?.isShowingUnreadMessageOnly ?? false,
            labelID: viewModel.labelID,
            user: viewModel.user,
            targetMessageID: targetID,
            userIntroduction: userCachedStatus,
            infoBubbleViewStatusProvider: infoBubbleViewStatusProvider,
            goToDraft: { [weak self] msgID, originalScheduledTime in
                self?.editScheduleMsg(messageID: msgID, originalScheduledTime: originalScheduledTime)
            }
        )
        presentPageViews(pageVM: pageVM)
    }

    private func presentPageViews<T, U, V>(pageVM: PagesViewModel<T, U, V>) {
        guard let navigationController = viewController?.navigationController else { return }
        var viewControllers = navigationController.viewControllers
        // if a placeholder VC is there, it has been presented with a push animation; avoid doing a 2nd one
        let animated = !(viewControllers.last is MessagePlaceholderVC)
        viewControllers.removeAll { !($0 is MailboxViewController) }
        let page = PagesViewController(viewModel: pageVM, services: services)
        viewControllers.append(page)
        navigationController.setViewControllers(viewControllers, animated: animated)
    }

    private func presentMessagePlaceholderIfNeeded() {
        guard let navigationController = viewController?.navigationController,
              !navigationController.viewControllers.contains(where: { $0 is MessagePlaceholderVC }) else { return }
        let placeholder = MessagePlaceholderVC()
        navigationController.pushViewController(placeholder, animated: true)
    }

    private func presentReferAFriend() {
        guard let referralLink = viewController?.viewModel.user.userInfo.referralProgram?.link else {
            return
        }
        let view = ReferralShareViewController(
            referralLink: referralLink
        )
        let navigation = UINavigationController(rootViewController: view)
        navigation.modalPresentationStyle = .fullScreen
        viewController?.present(navigation, animated: true)
    }

    private func resetNavigationViewControllersIfNeeded() {
        if let viewStack = viewController?.navigationController?.viewControllers,
           viewStack.count > 1,
           let firstVC = viewStack.first {
            viewController?.navigationController?.setViewControllers([firstVC], animated: false)
        }
    }
}
