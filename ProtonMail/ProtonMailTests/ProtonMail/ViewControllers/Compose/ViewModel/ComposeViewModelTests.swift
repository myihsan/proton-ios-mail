// Copyright (c) 2022 Proton AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import CoreData
import ProtonCore_DataModel
import ProtonCore_TestingToolkit
@testable import ProtonMail
import XCTest

final class ComposeViewModelTests: XCTestCase {
    private var mockCoreDataService: MockCoreDataContextProvider!
    private var apiMock: APIServiceMock!
    private var message: Message!
    private var testContext: NSManagedObjectContext!
    private var fakeUserManager: UserManager!
    private var sut: ComposeViewModel!
    private var contactProvider: MockContactProvider!

    override func setUp() {
        super.setUp()

        self.mockCoreDataService = MockCoreDataContextProvider()
        self.apiMock = APIServiceMock()

        testContext = MockCoreDataStore.testPersistentContainer.viewContext
        fakeUserManager = mockUserManager()
        contactProvider = .init(coreDataContextProvider: mockCoreDataService)

        let copyMessage = MockCopyMessageUseCase()

        copyMessage.executeStub.bodyIs { [unowned self] _, _ in
            (message, nil)
        }

        let helperDependencies = ComposerMessageHelper.Dependencies(
            messageDataService: fakeUserManager.messageService,
            cacheService: fakeUserManager.cacheService,
            contextProvider: mockCoreDataService,
            copyMessage: copyMessage
        )

        let dependencies = ComposeViewModel.Dependencies(
            coreDataContextProvider: mockCoreDataService,
            coreKeyMaker: MockKeyMakerProtocol(),
            fetchAndVerifyContacts: .init(),
            internetStatusProvider: .init(),
            fetchAttachment: .init(),
            contactProvider: contactProvider,
            helperDependencies: helperDependencies,
            fetchMobileSignatureUseCase: FetchMobileSignature(dependencies: .init(coreKeyMaker: MockKeyMakerProtocol(), cache: MockMobileSignatureCacheProtocol()))
        )

        self.message = testContext.performAndWait {
            Message(context: testContext)
        }

        sut = ComposeViewModel(
            msg: message,
            action: .openDraft,
            msgService: fakeUserManager.messageService,
            user: fakeUserManager,
            dependencies: dependencies
        )
    }

    override func tearDown() {
        self.sut = nil
        self.mockCoreDataService = nil
        self.apiMock = nil
        self.message = nil
        self.testContext = nil

        super.tearDown()
    }

    func testGetAttachment() {
        let attachment1 = Attachment(context: testContext)
        attachment1.order = 0
        attachment1.message = message
        let attachment2 = Attachment(context: testContext)
        attachment2.order = 1
        attachment2.message = message
        let attachmentSoftDeleted = Attachment(context: testContext)
        attachmentSoftDeleted.order = 3
        attachmentSoftDeleted.isSoftDeleted = true
        attachmentSoftDeleted.message = message

        let result = sut.getAttachments()
        // TODO: fix this test and uncomment this line, or replace the test, it's not meaningful
        // XCTAssertNotEqual(result, [])
        for index in result.indices {
            XCTAssertEqual(result[index].order, index)
        }
    }

    func testGetAddressesWhenMessageHeaderContainsFrom() {
        let addresses = generateAddress(number: 4)
        fakeUserManager.userInfo.set(addresses: addresses)

        let addressID = addresses[0].addressID
        let email1 = addresses[0].email
        let parts = email1.components(separatedBy: "@")
        let alias = "\(parts[0])+abcd@\(parts[1])"
        testContext.performAndWait {
            let obj = self.sut.composerMessageHelper.getRawMessageObject()
            obj?.parsedHeaders = "{\"From\": \"Tester <\(alias)>\"}"
        }
        let lists = sut.getAddresses()
        XCTAssertEqual(lists.count, 5)
        XCTAssertEqual(lists[0].email, alias)
        XCTAssertEqual(lists[0].addressID, addressID)
        XCTAssertEqual(lists.filter { $0.addressID == addressID }.count, 2)
    }

    func testGetAddressesWhenMessageHeaderWithoutFrom() {
        let addresses = generateAddress(number: Int.random(in: 2...8))
        fakeUserManager.userInfo.set(addresses: addresses)

        let lists = sut.getAddresses()
        XCTAssertEqual(lists.count, addresses.count)
        XCTAssertEqual(lists, addresses)
    }

    // MARK: isEmptyDraft tests

    func testIsEmptyDraft_messageInit() throws {
        sut.initialize(message: message, action: .openDraft)
        XCTAssertTrue(sut.isEmptyDraft())
    }

    func testIsEmptyDraft_subjectField() throws {
        message.title = "abc"
        sut.initialize(message: message, action: .openDraft)
        XCTAssertFalse(sut.isEmptyDraft())
    }

    func testIsEmptyDraft_recipientField() throws {
        message.toList = "[]"
        message.ccList = "[]"
        message.bccList = "[]"
        sut.initialize(message: message, action: .openDraft)

        XCTAssertTrue(sut.isEmptyDraft())
    }

    func testDecodingRecipients_prefersMatchingLocalContactName() throws {
        let email = EmailEntity.make(contactName: "My friend I don't like")

        contactProvider.getEmailsByAddressStub.bodyIs { _, _, _ in
            [email]
        }

        let backendResponse = "[{\"Address\": \"friend@example.com\", \"Name\": \"My friend\", \"Group\": \"\"}]"

        let contacts = sut.toContacts(backendResponse)
        let contact = try XCTUnwrap(contacts.first)
        XCTAssertEqual(contact.displayName, "My friend I don't like")
    }

    func testDecodingRecipients_usesBackendName_ifNoLocalContact() throws {
        let backendResponse = "[{\"Address\": \"friend@example.com\", \"Name\": \"My friend\", \"Group\": \"\"}]"

        let contacts = sut.toContacts(backendResponse)
        let contact = try XCTUnwrap(contacts.first)
        XCTAssertEqual(contact.displayName, "My friend")
    }

    func testDecodingRecipients_usesEmailAsDisplayName_ifNothingElseIsFound() throws {
        let backendResponsesWithoutProperName: [String] = [
            "[{\"Address\": \"friend@example.com\", \"Name\": \" \", \"Group\": \"\"}]",
            "[{\"Address\": \"friend@example.com\", \"Name\": \"\", \"Group\": \"\"}]",
            "[{\"Address\": \"friend@example.com\", \"Group\": \"\"}]"
        ]

        for backendResponse in backendResponsesWithoutProperName {
            let contacts = sut.toContacts(backendResponse)
            let contact = try XCTUnwrap(contacts.first)
            XCTAssertEqual(contact.displayName, "friend@example.com")
        }
    }
}

extension ComposeViewModelTests {
    private func mockUserManager() -> UserManager {
        let userInfo = UserInfo.getDefault()
        userInfo.defaultSignature = "Hi"
        let key = Key(keyID: "keyID", privateKey: KeyTestData.privateKey1)
        let address = Address(addressID: UUID().uuidString,
                              domainID: "",
                              email: "",
                              send: .active,
                              receive: .active,
                              status: .enabled,
                              type: .protonDomain,
                              order: 0,
                              displayName: "the name",
                              signature: "Hello",
                              hasKeys: 1,
                              keys: [key])
        userInfo.set(addresses: [address])
        return UserManager(api: self.apiMock, role: .owner, userInfo: userInfo)
    }

    func generateAddress(number: Int) -> [Address] {
        let key = Key(keyID: "keyID", privateKey: KeyTestData.privateKey1)
        let list = (0..<number).map { _ in
            let id = UUID().uuidString
            let domain = "\(String.randomString(3)).\(String.randomString(3))"
            let userPart = String.randomString(5)
            return Address(
                addressID: id,
                domainID: UUID().uuidString,
                email: "\(userPart)@\(domain)",
                send: .active,
                receive: .active,
                status: .enabled,
                type: .protonDomain,
                order: 0,
                displayName: String.randomString(7),
                signature: "Hello",
                hasKeys: 1,
                keys: [key]
            )
        }
        return list
    }
}
