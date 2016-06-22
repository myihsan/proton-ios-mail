//
//  MessageAPI.swift
//  ProtonMail
//
//  Created by Yanfeng Zhang on 6/18/15.
//  Copyright (c) 2015 ArcTouch. All rights reserved.
//

import Foundation


public class ComposeViewModel {
    var message : Message?
    var messageAction : ComposeMessageAction!
    var toSelectedContacts: [ContactVO]! = [ContactVO]()
    var ccSelectedContacts: [ContactVO]! = [ContactVO]()
    var bccSelectedContacts: [ContactVO]! = [ContactVO]()
    var contacts: [ContactVO]! = [ContactVO]()
    
    var subject : String! = ""
    var body : String! = ""
    
    var hasDraft : Bool {
        get{
            return message?.isDetailDownloaded ?? false
        }
    }
    var needsUpdate : Bool {
        get{
            return toChanged || ccChanged || bccChanged || titleChanged || bodyChanged
        }
    }
    
    var toChanged : Bool = false;
    var ccChanged : Bool = false;
    var bccChanged : Bool = false;
    var titleChanged : Bool = false;
    var bodyChanged : Bool = false;
    
    public init() { }
    
    public func getSubject() -> String {
        return self.subject
        //return self.message?.subject ?? ""
    }
    
    public func setSubject(sub : String) {
        self.subject = sub
    }
    
    public func setBody(body : String) {
        self.body = body
    }
    
    internal func addToContacts(contacts: ContactVO! ) {
        toSelectedContacts.append(contacts)
    }
    
    internal func addCcContacts(contacts: ContactVO! ) {
        ccSelectedContacts.append(contacts)
    }
    
    internal func addBccContacts(contacts: ContactVO! ) {
        bccSelectedContacts.append(contacts)
    }
    
    func getActionType() -> ComposeMessageAction {
        return messageAction
    }
    
    ///
    public func sendMessage() {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    public func updateDraft() {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    public func deleteDraft() {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    func uploadAtt(att : Attachment!) {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    func deleteAtt(att : Attachment!) {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    public func markAsRead() {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    public func getDefaultComposeBody() {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    public func getHtmlBody() -> String {
        NSException(name:"name", reason:"reason", userInfo:nil).raise()
        return ""
    }
    
    func collectDraft(title:String, body:String, expir:NSTimeInterval, pwd:String, pwdHit:String) -> Void {
         NSException(name:"name", reason:"reason", userInfo:nil).raise()
    }
    
    func getAttachments() -> [Attachment]? {
        fatalError("This method must be overridden")
    }
    
    func updateAddressID (address_id : String) {
        fatalError("This method must be overridden")
    }
    
    func getAddresses () -> Array<Address> {
        fatalError("This method must be overridden")
    }
   
    func getDefaultAddress () -> Address? {
        fatalError("This method must be overridden")
    }
    
    func getCurrrentSignature(addr_id : String) -> String? {
        fatalError("This method must be overridden")
    }
    
    func hasAttachment () -> Bool {
        fatalError("This method must be overridden")
    }
}



