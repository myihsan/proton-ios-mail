//
//  ContactGroupViewController.swift
//  ProtonMail
//
//  Created by Chun-Hung Tseng on 2018/8/17.
//  Copyright © 2018 ProtonMail. All rights reserved.
//

import UIKit
import CoreData
import PromiseKit

/**
 When the core data that provides data to this controller has data changes,
 the update will be performed immediately and automatically by core data
 */
class ContactGroupsViewController: ContactsAndGroupsSharedCode, ViewModelProtocol
{
    private var viewModel: ContactGroupsViewModel!
    private var queryString = ""
    
    // long press related vars
    private var isEditingState: Bool = false
    private let kLongPressDuration: CFTimeInterval = 0.60 // seconds
    private var trashcanBarButtonItem: UIBarButtonItem? = nil
    private var cancelBarButtonItem: UIBarButtonItem? = nil
    private var totalSelectedContactGroups: Int = 0 {
        didSet {
            if isEditingState {
                title = String.init(format: LocalString._contact_groups_selected_group_count_description,
                                    totalSelectedContactGroups)
            }
        }
    }
    
    private let kContactGroupCellIdentifier = "ContactGroupCustomCell"
    private let kToContactGroupDetailSegue = "toContactGroupDetailSegue"
    private let kToComposerSegue = "toComposer"
    
    private var fetchedContactGroupResultsController: NSFetchedResultsController<NSFetchRequestResult>? = nil
    private var refreshControl: UIRefreshControl!
    private var searchController: UISearchController!
    
    @IBOutlet weak var searchView: UIView!
    @IBOutlet weak var searchViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var tableView: UITableView!
    
    func setViewModel(_ vm: Any) {
        viewModel = vm as! ContactGroupsViewModel
    }
    
    func inactiveViewModel() {
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.definesPresentationContext = true
        self.extendedLayoutIncludesOpaqueBars = true
        
        prepareTable()
        
        prepareFetchedResultsController()
        
        prepareSearchBar()
        
        switch viewModel.getState() {
        case .ViewAllContactGroups:
            prepareRefreshController()
            prepareLongPressGesture()
            prepareNavigationItemRightDefault()
            updateNavigationBar()
        case .MultiSelectContactGroupsForContactEmail:
            isEditingState = true
            tableView.allowsMultipleSelection = true
            
            prepareNavigationItemTitle()
            
            self.navigationItem.leftBarButtonItem = self.navigationItem.backBarButtonItem
        }  
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if viewModel.getState() == .ViewAllContactGroups {
            self.viewModel.timerStart(true)
        }
        
        self.isOnMainView = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if viewModel.getState() == .ViewAllContactGroups {
            self.viewModel.timerStop()
        }
        
        viewModel.save()
    }
    
    private func prepareFetchedResultsController() {
        fetchedContactGroupResultsController = sharedLabelsDataService.fetchedResultsController(.contactGroup)
        fetchedContactGroupResultsController?.delegate = self
        if let fetchController = fetchedContactGroupResultsController {
            do {
                try fetchController.performFetch()
            } catch let error as NSError {
                PMLog.D("fetchedContactGroupResultsController Error: \(error.userInfo)")
            }
        }
    }
    
    private func prepareRefreshController() {
        refreshControl = UIRefreshControl()
        refreshControl.backgroundColor = UIColor(RRGGBB: UInt(0xDADEE8))
        refreshControl.addTarget(self,
                                 action: #selector(fireFetch),
                                 for: UIControl.Event.valueChanged)
        tableView.addSubview(self.refreshControl)
        refreshControl.tintColor = UIColor.gray
        refreshControl.tintColorDidChange()
    }
    
    private func prepareTable() {
        tableView.register(UINib(nibName: "ContactGroupsViewCell", bundle: Bundle.main),
                           forCellReuseIdentifier: kContactGroupCellIdentifier)
        
        tableView.noSeparatorsBelowFooter()
    }
    
    private func prepareLongPressGesture() {
        totalSelectedContactGroups = 0
        
        let longPressGestureRecognizer: UILongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress(_:)))
        longPressGestureRecognizer.minimumPressDuration = kLongPressDuration
        self.tableView.addGestureRecognizer(longPressGestureRecognizer)
    }
    
    @objc private func handleLongPress(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        // blocks contact group view from editing
        if sharedUserDataService.isPaidUser() == false {
            self.performSegue(withIdentifier: kToUpgradeAlertSegue,
                              sender: self)
            return
        }
        
        // mark the location that it is on
        markLongPressLocation(longPressGestureRecognizer)
    }
    
    private func markLongPressLocation(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        let pressingLocation = longPressGestureRecognizer.location(in: tableView)
        let pressedIndexPath = tableView.indexPathForRow(at: pressingLocation)
        
        if let pressedIndexPath = pressedIndexPath {
            if longPressGestureRecognizer.state == UIGestureRecognizer.State.began {
                // set state
                isEditingState = true
                tableView.allowsMultipleSelection = true
                
                // prepare the navigationItems
                updateNavigationBar()
                
                // set cell
                if let visibleIndexPaths = tableView.indexPathsForVisibleRows {
                    for visibleIndexPath in visibleIndexPaths {
                        if visibleIndexPath == pressedIndexPath {
                            // mark this indexPath as selected
                            if let cell = tableView.cellForRow(at: visibleIndexPath) as? ContactGroupsViewCell {
                                self.selectRow(at: visibleIndexPath, groupID: cell.getLabelID())
                            } else {
                                fatalError("Conversion failed")
                            }
                        }
                    }
                } else {
                    PMLog.D("No visible index path")
                }
            }
        } else {
            PMLog.D("Not long pressed on the cell")
        }
    }
    
    private func updateNavigationBar() {
        prepareNavigationItemLeft()
        prepareNavigationItemTitle()
        prepareNavigationItemRight()
    }
    
    private func prepareNavigationItemLeft() {
        if isEditingState {
            // make cancel button and selector
            if cancelBarButtonItem == nil {
                cancelBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(self.cancelBarButtonTapped))
            }
            
            navigationItem.leftBarButtonItems = [cancelBarButtonItem!]
        } else {
            // restore the left bar
            navigationItem.leftBarButtonItems = navigationItemLeftNotEditing
        }
    }
    
    // end long press event
    @objc private func cancelBarButtonTapped() {
        // reset state
        isEditingState = false
        tableView.allowsMultipleSelection = false
        
        // reset navigation bar
        updateNavigationBar()
        
        // unselect all
        totalSelectedContactGroups = 0
        viewModel.removeAllSelectedGroups()
        if let selectedIndexPaths = tableView.indexPathsForSelectedRows {
            for selectedIndexPath in selectedIndexPaths {
                tableView.deselectRow(at: selectedIndexPath,
                                      animated: true)
            }
        }
    }
    
    private func prepareNavigationItemTitle() {
        if isEditingState {
            self.title = String.init(format: LocalString._contact_groups_selected_group_count_description,
                                     0)
        } else {
            self.title = LocalString._menu_contact_group_title
        }
    }
    
    private func prepareNavigationItemRight() {
        if isEditingState {
            // make trash can and selector
            if trashcanBarButtonItem == nil {
                trashcanBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .trash,
                                                             target: self,
                                                             action: #selector(self.trashcanBarButtonTapped))
            }
            
            navigationItem.rightBarButtonItems = [trashcanBarButtonItem!]
        } else {
            // restore the right bar
            navigationItem.rightBarButtonItems = navigationItemRightNotEditing
        }
    }
    
    private func resetStateFromMultiSelect()
    {
        // reset state
        self.isEditingState = false
        self.tableView.allowsMultipleSelection = false
        self.totalSelectedContactGroups = 0
        
        // reset navigation bar
        self.updateNavigationBar()
    }
    
    @objc private func trashcanBarButtonTapped() {
        let deleteHandler = {
            (action: UIAlertAction) -> Void in
            firstly {
                () -> Promise<Void> in
                // attempt to delete selected groups
                ActivityIndicatorHelper.showActivityIndicator(at: self.view)
                return self.viewModel.deleteGroups()
                }.done {
                    self.resetStateFromMultiSelect()
                }.ensure {
                    ActivityIndicatorHelper.hideActivityIndicator(at: self.view)
                }.catch {
                    error in
                    error.alert(at: self.view)
            }
        }
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: LocalString._general_cancel_button,
                                                style: .cancel, handler: nil))
        alertController.addAction(UIAlertAction(title: LocalString._contact_groups_delete,
                                                style: .destructive,
                                                handler: deleteHandler))
        
        alertController.popoverPresentationController?.sourceView = self.view
        alertController.popoverPresentationController?.sourceRect = self.view.frame
        self.present(alertController, animated: true, completion: nil)
    }
    
    private func prepareSearchBar() {
        viewModel.setFetchResultController(fetchedResultsController: &fetchedContactGroupResultsController)
        
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.placeholder = LocalString._general_search_placeholder
        searchController.searchBar.setValue(LocalString._general_cancel_button,
                                            forKey:"_cancelButtonText")
        
        self.searchController.searchResultsUpdater = self
        self.searchController.dimsBackgroundDuringPresentation = false
        self.searchController.searchBar.delegate = self
        self.searchController.hidesNavigationBarDuringPresentation = true
        self.searchController.automaticallyAdjustsScrollViewInsets = true
        self.searchController.searchBar.sizeToFit()
        self.searchController.searchBar.keyboardType = .default
        self.searchController.searchBar.autocapitalizationType = .none
        self.searchController.searchBar.isTranslucent = false
        self.searchController.searchBar.tintColor = .white
        self.searchController.searchBar.barTintColor = UIColor.ProtonMail.Nav_Bar_Background
        self.searchController.searchBar.backgroundColor = .clear
        
        if #available(iOS 11.0, *) {
            self.searchViewConstraint.constant = 0.0
            self.searchView.isHidden = true
            self.navigationItem.largeTitleDisplayMode = .never
            self.navigationItem.hidesSearchBarWhenScrolling = false
            self.navigationItem.searchController = self.searchController
        } else {
            self.searchViewConstraint.constant = self.searchController.searchBar.frame.height
            self.searchView.backgroundColor = UIColor.ProtonMail.Nav_Bar_Background
            self.searchView.addSubview(self.searchController.searchBar)
            self.searchController.searchBar.contactSearchSetup(textfieldBG: UIColor.init(hexColorCode: "#82829C"),
                                                               placeholderColor: UIColor.init(hexColorCode: "#BBBBC9"), textColor: .white)
        }
    }
    
    @objc func fireFetch() {
        firstly {
            return self.viewModel.fetchLatestContactGroup()
            }.done {
                self.refreshControl.endRefreshing()
            }.catch {
                error in
                
                let alert = UIAlertController(title: LocalString._contact_groups_fetch_error,
                                              message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addOKAction()
                
                self.present(alert,
                             animated: true,
                             completion: nil)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        self.isOnMainView = false // hide the tab bar
        
        if segue.identifier == kToContactGroupDetailSegue {
            let contactGroupDetailViewController = segue.destination as! ContactGroupDetailViewController
            let contactGroup = sender as! Label
            sharedVMService.contactGroupDetailViewModel(contactGroupDetailViewController,
                                                        groupID: contactGroup.labelID,
                                                        name: contactGroup.name,
                                                        color: contactGroup.color,
                                                        emailIDs: contactGroup.emails)
        } else if (segue.identifier == kAddContactSugue) {
            let addContactViewController = segue.destination.children[0] as! ContactEditViewController
            sharedVMService.contactAddViewModel(addContactViewController)
        } else if (segue.identifier == kAddContactGroupSugue) {
            let addContactGroupViewController = segue.destination.children[0] as! ContactGroupEditViewController
            sharedVMService.contactGroupEditViewModel(addContactGroupViewController, state: .create)
        } else if segue.identifier == kSegueToImportView {
            let popup = segue.destination as! ContactImportViewController
            self.setPresentationStyleForSelfController(self,
                                                       presentingController: popup,
                                                       style: .overFullScreen)
        } else if segue.identifier == kToComposerSegue {
            let destination = segue.destination.children[0] as! ComposeEmailViewController
            
            if let result = sender as? (String, String) {
                let contactGroupVO = ContactGroupVO.init(ID: result.0, name: result.1)
                sharedVMService.newDraft(vmp: destination, with: contactGroupVO)
            }
        } else if segue.identifier == kToUpgradeAlertSegue {
            let popup = segue.destination as! UpgradeAlertViewController
            popup.delegate = self
            sharedVMService.upgradeAlert(contacts: popup)
            self.setPresentationStyleForSelfController(self,
                                                       presentingController: popup,
                                                       style: .overFullScreen)
        }
    }
    
    func selectRow(at indexPath: IndexPath, groupID: String) {
        tableView.selectRow(at: indexPath,
                            animated: true,
                            scrollPosition: .none)
        
        viewModel.addSelectedGroup(ID: groupID, indexPath: indexPath)
        totalSelectedContactGroups = viewModel.getSelectedCount()
    }
    
    func deselectRow(at indexPath: IndexPath, groupID: String) {
        tableView.deselectRow(at: indexPath,
                              animated: true)
        
        viewModel.removeSelectedGroup(ID: groupID, indexPath: indexPath)
        totalSelectedContactGroups = viewModel.getSelectedCount()
    }
}

extension ContactGroupsViewController: UISearchBarDelegate, UISearchResultsUpdating
{
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.search(text: searchController.searchBar.text)
        queryString = searchController.searchBar.text ?? ""
        tableView.reloadData()
    }
}

extension ContactGroupsViewController: UITableViewDataSource
{
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch viewModel.getState() {
        case .MultiSelectContactGroupsForContactEmail:
            return viewModel.totalRows()
        case .ViewAllContactGroups:
            if let fetchedController = fetchedContactGroupResultsController {
                return fetchedController.fetchedObjects?.count ?? 0
            }
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = self.tableView.dequeueReusableCell(withIdentifier: kContactGroupCellIdentifier, for: indexPath)
        
        if let cell = cell as? ContactGroupsViewCell {
            switch viewModel.getState() {
            case .MultiSelectContactGroupsForContactEmail:
                let data = viewModel.cellForRow(at: indexPath)
                cell.config(labelID: data.ID,
                            name: data.name,
                            queryString: self.queryString,
                            count: data.count,
                            color: data.color,
                            wasSelected: viewModel.isSelected(groupID: data.ID),
                            delegate: self)
                if viewModel.isSelected(groupID: data.ID) {
                    tableView.selectRow(at: indexPath,
                                        animated: true,
                                        scrollPosition: .none)
                }
            case .ViewAllContactGroups:
                if let fetchedController = fetchedContactGroupResultsController {
                    if let label = fetchedController.object(at: indexPath) as? Label {
                        cell.config(labelID: label.labelID,
                                    name: label.name,
                                    queryString: self.queryString,
                                    count: label.emails.count,
                                    color: label.color,
                                    wasSelected: false,
                                    delegate: self)
                        
                        if viewModel.isSelected(groupID: label.labelID) {
                            tableView.selectRow(at: indexPath,
                                                animated: true,
                                                scrollPosition: .none)
                        }
                    } else {
                        // TODO: better error handling
                        cell.config(labelID: "",
                                    name: "Error in retrieving contact group name in core data",
                                    queryString: "",
                                    count: 0,
                                    color: ColorManager.defaultColor,
                                    wasSelected: false,
                                    delegate: self)
                    }
                }
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? ContactGroupsViewCell {
            if viewModel.getState() == .MultiSelectContactGroupsForContactEmail {
                if viewModel.isSelected(groupID: cell.getLabelID()) {
                    self.selectRow(at: indexPath, groupID: cell.getLabelID())
                }
            }
        } else {
            PMLog.D("Downcasting failed")
        }
    }
}

extension ContactGroupsViewController: ContactGroupsViewCellDelegate
{
    func isMultiSelect() -> Bool {
        return isEditingState || viewModel.getState() == .MultiSelectContactGroupsForContactEmail
    }
    
    func sendEmailToGroup(ID: String, name: String) {
        if sharedUserDataService.isPaidUser() {
            self.performSegue(withIdentifier: kToComposerSegue, sender: (ID: ID, name: name))
        } else {
            self.performSegue(withIdentifier: kToUpgradeAlertSegue, sender: self)
        }
    }
}

extension ContactGroupsViewController: UITableViewDelegate
{
    func tableView(_ tableView: UITableView,
                   editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        self.resetStateFromMultiSelect()
        
        let deleteHandler = {
            (action: UITableViewRowAction, indexPath: IndexPath) -> Void in
            
            let deleteActionHandler = {
                (action: UIAlertAction) -> Void in
                
                firstly {
                    () -> Promise<Void> in
                    // attempt to delete selected groups
                    ActivityIndicatorHelper.showActivityIndicator(at: self.view)
                    if let cell = self.tableView.cellForRow(at: indexPath) as? ContactGroupsViewCell {
                        self.viewModel.addSelectedGroup(ID: cell.getLabelID(),
                                                        indexPath: indexPath)
                    }
                    return self.viewModel.deleteGroups()
                    }.ensure {
                        ActivityIndicatorHelper.hideActivityIndicator(at: self.view)
                    }.catch {
                        error in
                        error.alert(at: self.view)
                }
            }

            let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            alertController.addAction(UIAlertAction(title: LocalString._general_cancel_button,
                                                    style: .cancel,
                                                    handler: nil))
            alertController.addAction(UIAlertAction(title: LocalString._contact_groups_delete,
                                                    style: .destructive,
                                                    handler: deleteActionHandler))

            alertController.popoverPresentationController?.sourceView = self.view
            alertController.popoverPresentationController?.sourceRect = self.view.frame
            self.present(alertController, animated: true, completion: nil)
        }
        
        let deleteAction = UITableViewRowAction.init(style: .destructive,
                                                     title: LocalString._general_delete_action,
                                                     handler: deleteHandler)
        return [deleteAction]
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditingState {
            // blocks contact email cell contact group editing
            if sharedUserDataService.isPaidUser() == false {
                tableView.deselectRow(at: indexPath, animated: true)
                self.performSegue(withIdentifier: kToUpgradeAlertSegue, sender: self)
                return
            }
            
            if let cell = tableView.cellForRow(at: indexPath) as? ContactGroupsViewCell {
                self.selectRow(at: indexPath, groupID: cell.getLabelID())
                
                if viewModel.getState() == .MultiSelectContactGroupsForContactEmail {
                    cell.setCount(viewModel.cellForRow(at: indexPath).count)
                }
            } else {
                fatalError("Conversion failed")
            }
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
            
            if let fetchedController = fetchedContactGroupResultsController {
                self.performSegue(withIdentifier: kToContactGroupDetailSegue,
                                  sender: fetchedController.object(at: indexPath))
            }
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditingState {
            // blocks contact email cell contact group editing
            if sharedUserDataService.isPaidUser() == false {
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
                self.performSegue(withIdentifier: kToUpgradeAlertSegue, sender: self)
                return
            }
            
            if let cell = tableView.cellForRow(at: indexPath) as? ContactGroupsViewCell {
                self.deselectRow(at: indexPath, groupID: cell.getLabelID())
                
                if viewModel.getState() == .MultiSelectContactGroupsForContactEmail {
                    if viewModel.getState() == .MultiSelectContactGroupsForContactEmail {
                        cell.setCount(viewModel.cellForRow(at: indexPath).count)
                    }
                }
            } else {
                fatalError("Conversion failed")
            }
        }
    }
}

extension ContactGroupsViewController: UpgradeAlertVCDelegate {
    func goPlans() {
        self.navigationController?.dismiss(animated: false, completion: {
            NotificationCenter.default.post(name: .switchView,
                                            object: MenuItem.servicePlan)
        })
    }
    
    func learnMore() {
        UIApplication.shared.openURL(URL(string: "https://protonmail.com/support/knowledge-base/paid-plans/")!)
    }
    
    func cancel() {
        
    }
}

extension ContactGroupsViewController: NSFetchedResultsControllerDelegate
{
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: UITableView.RowAnimation.fade)
            }
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: UITableView.RowAnimation.fade)
            }
        case .update:
            if let cell = tableView.cellForRow(at: indexPath!) as? ContactGroupsViewCell {
                if let fetchedController = fetchedContactGroupResultsController {
                    if let label = fetchedController.object(at: indexPath!) as? Label {
                        cell.config(labelID: label.labelID,
                                    name: label.name,
                                    queryString: self.queryString,
                                    count: label.emails.count,
                                    color: label.color,
                                    wasSelected: false,
                                    delegate: self)
                    } else {
                        // TODO; better error handling
                        cell.config(labelID: "",
                                    name: "Error in retrieving contact group name in core data",
                                    queryString: "",
                                    count: 0,
                                    color: ColorManager.defaultColor,
                                    wasSelected: false,
                                    delegate: self)
                    }
                }
            }
        case .move: // group order might change! (renaming)
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
            
            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
            
            return
        }
    }
}
