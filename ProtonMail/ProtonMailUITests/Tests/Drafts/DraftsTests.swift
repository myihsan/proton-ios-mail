//
//  DraftsTests.swift
//  ProtonMailUITests
//
//  Created by denys zelenchuk on 08.10.20.
//  Copyright © 2020 Proton Mail. All rights reserved.
//

import ProtonCore_TestingToolkit

class DraftsTests: FixtureAuthenticatedTestCase {
    private var subject = String()
    private var body = String()
    private var to = String()

    private var composerRobot: ComposerRobot!

    override func setUp() {
        super.setUp()
        subject = testData.messageSubject
        body = testData.messageBody
        to = testData.twoPassUser.email

        composerRobot = InboxRobot().compose()
    }

    func testSaveDraft() {
        composerRobot
            .draftToSubjectBody(to, subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .verify.messageWithSubjectExists(subject)
    }

    func testSaveDraftWithAttachment() {
        composerRobot
            .draftToSubjectBodyAttachment(to,subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .verify.messageWithSubjectExists(subject)
    }

    func testOpenDraftFromSearch() {
        composerRobot
            .draftSubjectBody(subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .searchBar()
            .searchMessageText(subject)
            .clickSearchedDraftBySubject(subject)
            .verify.messageWithSubjectOpened(subject)
    }

    func testSendDraftWithAttachment() {
        composerRobot
            .draftToSubjectBodyAttachment(to, subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(subject)
            .send()
            .menuDrawer()
            .sent()
            .refreshMailbox()
            .verify.messageWithSubjectExists(subject)
    }

    // 34849
    func testAddRecipientsToDraft() {
        let to = testData.internalEmailTrustedKeys.email
        composerRobot
            .draftSubjectBody(subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(subject)
            .typeAndSelectRecipients(to)
            .tapCancelFromDrafts()
            .verify.messageWithSubjectAndRecipientExists(subject, to)
    }

    func disabledChangeDraftSender() {
        let onePassUserSecondEmail = "2\(testData.onePassUser.email)"

        composerRobot
            .draftSubjectBody(subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(subject)
            .changeFromAddressTo(onePassUserSecondEmail)
            .tapCancelFromDrafts()
            .clickDraftBySubject(subject)
            .verify.fromEmailIs(onePassUserSecondEmail)
    }
    
    func testChangeDraftSubjectAndSendMessage() {
        let newSubject = testData.messageSubject

        composerRobot
            .draftToSubjectBody(to, subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(subject)
            .changeSubjectTo(newSubject)
            .send()
            .menuDrawer()
            .sent()
            .verify.messageWithSubjectExists(newSubject)
    }
    
    /// TestId: 34636
    func testSaveDraftWithoutSubject() {
        let noSubject = "(No Subject)"
        composerRobot
            .draftToBody(to, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftByIndex(0)
            .send()
            .menuDrawer()
            .sent()
            .verify.messageExists(noSubject)
    }
    
    /// TestId: 34640
    func testMinimiseAppWhileComposingDraft() {
        composerRobot
            .draftToSubjectBody(to, subject, body)
            .backgroundApp()
            .foregroundApp()
            .tapCancel()
            .menuDrawer()
            .drafts()
            .verify.messageWithSubjectExists(subject)
    }
    
    /// TestId: 35877
    func testEditDraftMinimiseAppAndSend() {
        let newRecipient = testData.onePassUserWith2Fa.email
        let newSubject = testData.newMessageSubject
        composerRobot
            .draftToSubjectBody(to, subject, body)
            .backgroundApp()
            .foregroundApp()
            .editRecipients(newRecipient)
            .changeSubjectTo(newSubject)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(newSubject)
            .send()
            .menuDrawer()
            .sent()
            .verify.messageWithSubjectExists(newSubject)
    }
    
    /// TestId: 34634
    func testEditDraftMultipleTimesAndSend() {
        let editOneRecipient = testData.onePassUserWith2Fa.email
        let editTwoRecipient = testData.twoPassUserWith2Fa.email
        let editOneSubject = "Edit one \(Date().millisecondsSince1970)"
        let editTwoSubject = "Edit two \(Date().millisecondsSince1970)"
        composerRobot
            .draftToSubjectBody(to, subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(subject)
            .editRecipients(editOneRecipient)
            .changeSubjectTo(editOneSubject)
            .tapCancelFromDrafts()
            .clickDraftBySubject(editOneSubject)
            .editRecipients(editTwoRecipient)
            .changeSubjectTo(editTwoSubject)
            .tapCancelFromDrafts()
            .verify.messageWithSubjectExists(editTwoSubject)
    }
    
    /// TestId: 35856
    func testEditEveryFieldInDraftWithEnabledPublicKeyAndSend() {
        let newRecipient = testData.onePassUserWith2Fa.email
        let newSubject = testData.newMessageSubject
        composerRobot
            .draftToSubjectBody(testData.onePassUser.email, subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(subject)
            .editRecipients(newRecipient)
            .changeSubjectTo(newSubject)
            .tapCancelFromDrafts()
            .clickDraftBySubject(newSubject)
            .send()
            .menuDrawer()
            .sent()
            .verify.messageWithSubjectExists(newSubject)
    }
    
    /// TestId: 35854
    func testEditDraftWithEnabledPublicKeyMultipleTimesAndSend() {
        let editOneRecipient = testData.onePassUserWith2Fa.email
        let editTwoRecipient = testData.onePassUser.email
        let editOneSubject = "Edit one \(Date().millisecondsSince1970)"
        let editTwoSubject = "Edit two \(Date().millisecondsSince1970)"
        composerRobot
            .draftToSubjectBody(testData.onePassUser.email, subject, body)
            .tapCancel()
            .menuDrawer()
            .drafts()
            .clickDraftBySubject(subject)
            .editRecipients(editOneRecipient)
            .changeSubjectTo(editOneSubject)
            .tapCancelFromDrafts()
            .clickDraftBySubject(editOneSubject)
            .editRecipients(editTwoRecipient)
            .changeSubjectTo(editTwoSubject)
            .tapCancelFromDrafts()
            .verify.messageWithSubjectExists(editTwoSubject)
    }
}
