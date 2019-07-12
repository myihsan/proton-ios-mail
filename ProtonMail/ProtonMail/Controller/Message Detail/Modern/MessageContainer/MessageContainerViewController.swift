//
//  ModernMessageViewController.swift
//  ProtonMail - Created on 06/03/2019.
//
//
//  The MIT License
//
//  Copyright (c) 2018 Proton Technologies AG
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


import UIKit
import MBProgressHUD


class MessageContainerViewController: TableContainerViewController<MessageContainerViewModel, MessageContainerViewCoordinator> {
    @IBOutlet weak var bottomView: MessageDetailBottomView! // TODO: this can be tableView section footer in conversation mode
    private var threadObservation: NSKeyValueObservation!
    private var standalonesObservation: [NSKeyValueObservation] = []
    
    override func viewDidLoad() {
        self.restorationClass = MessageContainerViewController.self
        super.viewDidLoad()
        
        // child view controllers
        self.coordinator.createChildControllers(with: self.viewModel)
        
        // navigation bar buttons
        let moreButton = UIBarButtonItem(image: UIImage.Top.more, style: .plain, target: self, action: #selector(topMoreButtonTapped))
        moreButton.accessibilityLabel = LocalString._general_more
        let trashButton = UIBarButtonItem(image: UIImage.Top.trash, style: .plain, target: self, action: #selector(topTrashButtonTapped))
        trashButton.accessibilityLabel = LocalString._menu_trash_title
        let folderButton = UIBarButtonItem(image: UIImage.Top.folder, style: .plain, target: self, action: #selector(topFolderButtonTapped))
        folderButton.accessibilityLabel = LocalString._move_to_
        let labelButton = UIBarButtonItem(image: UIImage.Top.label, style: .plain, target: self, action: #selector(topLabelButtonTapped))
        labelButton.accessibilityLabel = LocalString._label_as_
        let unreadButton = UIBarButtonItem(image: UIImage.Top.unread, style: .plain, target: self, action: #selector(topUnreadButtonTapped))
        unreadButton.accessibilityLabel = LocalString._mark_as_unread
        self.navigationItem.setRightBarButtonItems([moreButton, trashButton, folderButton, labelButton, unreadButton], animated: true)
        
        // others
        self.bottomView.delegate = self
    }
    
    @objc func topMoreButtonTapped(_ sender: UIBarButtonItem) { 
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: LocalString._general_cancel_button, style: .cancel, handler: nil))
        
        self.viewModel.locationsForMoreButton().map { location -> UIAlertAction in
            .init(title: location.actionTitle, style: .default) { [weak self] _ in
                self?.viewModel.moveThread(to: location)
                self?.coordinator.dismiss()
            }
        }.forEach(alertController.addAction)
        
        alertController.addAction(UIAlertAction(title: LocalString._print, style: .default, handler: self.printButtonTapped))
        alertController.addAction(UIAlertAction.init(title: LocalString._view_message_headers, style: .default, handler: self.viewHeadersButtonTapped))
        alertController.addAction(.init(title: LocalString._report_phishing, style: .destructive, handler: { _ in
            let alert = UIAlertController(title: LocalString._confirm_phishing_report,
                                          message: LocalString._reporting_a_message_as_a_phishing_,
                                          preferredStyle: .alert)
            alert.addAction(.init(title: LocalString._general_cancel_button, style: .cancel, handler: { _ in }))
            alert.addAction(.init(title: LocalString._general_confirm_action, style: .default, handler: self.reportPhishingButtonTapped))
            self.present(alert, animated: true, completion: nil)
        }))
        
        alertController.popoverPresentationController?.barButtonItem = sender
        alertController.popoverPresentationController?.sourceRect = self.view.frame
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    @objc func reportPhishingButtonTapped(_ sender: Any) {
        MBProgressHUD.showAdded(to: self.view, animated: true)
        self.viewModel.reportPhishing() { error in
            guard error == nil else {
                let alert = error!.alertController()
                alert.addOKAction()
                self.present(alert, animated: true, completion: nil)
                return
            }
            self.viewModel.moveThread(to: .spam)
            self.coordinator.dismiss()
        }
    }
    @objc func printButtonTapped(_ sender: Any) {
        let children = self.coordinator.printableChildren()
        // here we can add printable cells data if needed
        let childrenData = children.map { $0.printPageRenderer() }
        let url = self.viewModel.print(childrenData)
        self.coordinator.previewQuickLook(for: url)
    }
    @objc func viewHeadersButtonTapped(_ sender: Any) {
        let url = self.viewModel.headersTemporaryUrl()
        self.coordinator.previewQuickLook(for: url)
    }
    @objc func topTrashButtonTapped(_ sender: UIBarButtonItem) {
        func remove() {
            self.viewModel.removeThread()
            self.coordinator.dismiss()
        }
        
        guard self.viewModel.isRemoveIrreversible() else {
            remove()
            return
        }
        
        let alert = UIAlertController(title: LocalString._warning, message: LocalString._messages_will_be_removed_irreversibly, preferredStyle: .alert)
        let yes = UIAlertAction(title: LocalString._general_delete_action, style: .destructive) { _ in remove() }
        let cancel = UIAlertAction(title: LocalString._general_cancel_button, style: .cancel, handler: { _ in /* nothing */ })
        [yes, cancel].forEach(alert.addAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    @objc func topFolderButtonTapped(_ sender: UIBarButtonItem) {
        self.coordinator.go(to: .folders)
    }
    @objc func topLabelButtonTapped() {
        self.coordinator.go(to: .labels)
    }
    @objc func topUnreadButtonTapped(_ sender: UIBarButtonItem) {
        self.viewModel.markThread(read: false)
        self.coordinator.dismiss()
    }
    
    deinit {
        self.standalonesObservation = []
        self.threadObservation = nil
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // FIXME: this is good only for labels and folders
        self.coordinator.prepare(for: segue, sender: self.viewModel.messages)
    }

    // --
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let standalone = self.viewModel.thread[indexPath.section]
        switch standalone.divisions[indexPath.row] {
        case .remoteContent:
            guard let newCell = self.tableView.dequeueReusableCell(withIdentifier: String(describing: ShowImageCell.self), for: indexPath) as? ShowImageCell else
            {
                fatalError("Failed to dequeue ShowImageCell")
            }
            newCell.showImageView.delegate = self
            return newCell
            
        case .expiration:
            guard let newCell = self.tableView.dequeueReusableCell(withIdentifier: String(describing: ExpirationCell.self), for: indexPath) as? ExpirationCell,
                let expiration = standalone.expiration else
            {
                fatalError("Failed to dequeue ExpirationCell")
            }
            newCell.set(expiration: expiration)
            return newCell
            
        default:
            return super.tableView(tableView, cellForRowAt: indexPath)
        }
    }

    // --
    
    private func subscribeToThread() {
        self.threadObservation = self.viewModel.observe(\.thread) { [weak self] viewModel, change in
            guard let self = self else { return }
            self.standalonesObservation = []
            viewModel.thread.forEach(self.subscribeToStandalone)
        }
    }
    
    private func subscribeToStandalone(_ standalone: MessageViewModel) {
        let head = standalone.observe(\.heightOfHeader) { [weak self] _, _ in
            self?.tableView.beginUpdates()
            self?.tableView.endUpdates()
        }
        self.standalonesObservation.append(head)
        
        let attachments = standalone.observe(\.heightOfAttachments) { [weak self] standalone, _ in
            guard let section = self?.viewModel.thread.firstIndex(of: standalone) else { return}
            let indexPath = IndexPath(row: MessageViewModel.Divisions.attachments.rawValue, section: section)
            self?.tableView.reloadRows(at: [indexPath], with: .fade)
        }
        self.standalonesObservation.append(attachments)
        
        let body = standalone.observe(\.heightOfBody) { [weak self] _, _ in
            // this super-short animation duration will make animation invisible, otherwise it looks like cell is unfolding from top to bottom with a default 0.3s duration and resizing afrer zoom looks jumpy
            UIView.animate(withDuration: 0.001, animations: {
                self?.saveOffset()
                self?.tableView.beginUpdates()
                self?.tableView.endUpdates()
                self?.restoreOffset()
            })
        }
        self.standalonesObservation.append(body)
        
        let divisions = standalone.observe(\.divisionsCount, options: [.new, .old]) { [weak self] standalone, change in
            guard let old = change.oldValue, let new = change.newValue, old != new else { return }
            if let index = self?.viewModel.thread.firstIndex(of: standalone) {
                self?.tableView.reloadSections(IndexSet(integer: index), with: .fade)
            }
        }
        self.standalonesObservation.append(divisions)
    }
    
    override func set(viewModel: MessageContainerViewModel) {
        super.set(viewModel: viewModel)
        
        viewModel.thread.forEach(self.subscribeToStandalone)
        self.subscribeToThread()
        self.viewModel.downloadThreadDetails()
    }
}

extension MessageContainerViewController: ShowImageViewDelegate {
    func showImage() { // TODO: this should tell us which cell was tapped to let per-message switch in conversation mode
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        self.viewModel.thread.forEach { $0.remoteContentMode = .allowed }
    }
}

extension MessageContainerViewController: MessageDetailBottomViewDelegate {
    func replyAction() {
        self.coordinator.go(to: .composerReply)
    }
    func replyAllAction() {
        self.coordinator.go(to: .composerReplyAll)
    }
    func forwardAction() {
        self.coordinator.go(to: .composerForward)
    }
}

extension MessageContainerViewController: UIViewControllerRestoration {
    static func viewController(withRestorationIdentifierPath identifierComponents: [String], coder: NSCoder) -> UIViewController? {
        let next = UIStoryboard(name: "Message", bundle: .main).make(MessageContainerViewController.self)
        
        guard let data = coder.decodeObject() as? Data,
            let messageID = String(data: data, encoding: .utf8),
            let message = sharedMessageDataService.fetchMessages(withIDs: NSMutableSet(array: [messageID])).first else
        {
                return nil
        }
            
        next.set(viewModel: .init(message: message))
        next.set(coordinator: .init(controller: next))
        
        return next
    }
    
    override func encodeRestorableState(with coder: NSCoder) {
        if let messageID = self.viewModel.messages.first?.messageID {
            coder.encode(messageID.data(using: .utf8))
        }
        super.encodeRestorableState(with: coder)
    }
}
