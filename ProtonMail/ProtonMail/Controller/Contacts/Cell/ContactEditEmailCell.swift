//
//  ContactEditEmailCell.swift
//  ProtonMail
//
//  Created by Yanfeng Zhang on 5/4/17.
//  Copyright © 2017 ProtonMail. All rights reserved.
//

import Foundation



final class ContactEditEmailCell: UITableViewCell {
    
    fileprivate var email: ContactEditEmail!
    
    fileprivate var delegate: ContactEditCellDelegate?
    
    @IBOutlet weak var groupButton: UIButton!
    @IBOutlet weak var iconStackView: UIStackView!
    @IBOutlet weak var iconStackViewWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var typeButton: UIButton!
    @IBOutlet weak var valueField: UITextField!
    @IBOutlet weak var sepratorView: UIView!
    @IBOutlet weak var horizontalSeparator: UIView!
    
    var firstSetup = true
    
    func configCell(obj: ContactEditEmail,
                    callback: ContactEditCellDelegate?,
                    becomeFirstResponder: Bool = false) {
        self.email = obj
        
        
        typeButton.setTitle(self.email.newType.title,
                            for: .normal)
        valueField.text = self.email.newEmail
        self.delegate = callback
        
        if becomeFirstResponder {
            delay(0.25, closure: {
                self.valueField.becomeFirstResponder()
            })
        }
        
        // setup group icons
        prepareContactGroupIcons(cell: self,
                                 contactGroupColors: self.email.getCurrentlySelectedContactGroupColors(),
                                 iconStackView: iconStackView,
                                 iconStackViewWidthConstraint: iconStackViewWidthConstraint)
        
        if firstSetup {
            // setup gesture recognizer
            let tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                              action: #selector(didTapGroupViewStack(sender:)))
            tapGestureRecognizer.numberOfTapsRequired = 1
            iconStackView.isUserInteractionEnabled = true
            iconStackView.addGestureRecognizer(tapGestureRecognizer)
            
            firstSetup = false
        }
    }
    
    // called when the contact group selection view is dismissed
    func refreshHandler(updatedContactGroups: Set<String>)
    {
        email.updateContactGroups(updatedContactGroups: updatedContactGroups)
        prepareContactGroupIcons(cell: self,
                                 contactGroupColors: self.email.getCurrentlySelectedContactGroupColors(),
                                 iconStackView: iconStackView,
                                 iconStackViewWidthConstraint: iconStackViewWidthConstraint)
    }
    
    func getCurrentlySelectedContactGroupsID() -> Set<String> {
        return email.getCurrentlySelectedContactGroupsID()
    }
    

    @IBAction func didTapGroupButton(_ sender: UIButton) {
        delegate?.toSelectContactGroups(sender: self)
    }
    
    @objc func didTapGroupViewStack(sender: UITapGestureRecognizer) {
        delegate?.toSelectContactGroups(sender: self)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.valueField.delegate = self
        self.valueField.placeholder = LocalString._contacts_email_address_placeholder
    }
    
    @IBAction func typeAction(_ sender: UIButton) {
        delegate?.pick(typeInterface: email, sender: self)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        sepratorView.gradient()
        horizontalSeparator.gradient()
    }
}

extension ContactEditEmailCell: ContactCellShare {}

extension ContactEditEmailCell: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        delegate?.beginEditing(textField: textField)
    }
    
    func textFieldDidEndEditing(_ textField: UITextField)  {
        email.newEmail = valueField.text!
    }
}
