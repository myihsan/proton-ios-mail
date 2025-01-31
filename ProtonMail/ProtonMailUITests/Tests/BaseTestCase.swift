//
//  BaseTest.swift
//  ProtonMailUITests
//
//  Created by denys zelenchuk on 03.07.20.
//  Copyright © 2020 Proton Mail. All rights reserved.
//

import Foundation
import XCTest
import fusion
@testable import ProtonMail
import ProtonCore_Environment
import ProtonCore_QuarkCommands
import ProtonCore_TestingToolkit
import Yams

let apiDomainKey = "MAIL_APP_API_DOMAIN"
var environmentFileName = "environment"
var credentialsFileName = "credentials"
let credentialsBlackFileName = "credentials_black"
let testData = TestData()
var users: [String: TestUser] = [:]

var dynamicDomain: String {
    ProcessInfo.processInfo.environment["DYNAMIC_DOMAIN"] ?? ""
}

/**
 Parent class for all the test classes.
 */
class BaseTestCase: CoreTestCase, QuarkTestable {
    
    var launchArguments = ["-clear_all_preference", "YES"]
    var humanVerificationStubs = false
    var forceUpgradeStubs = false
    var extAccountNotSupportedStub = false
    var usesBlackCredentialsFile = true
    private let loginRobot = LoginRobot()

    var env: Environment = .black
    lazy var quarkCommands = QuarkCommands(doh: env.doh)

    func terminateApp() {
        app.terminate()
    }

    /// Runs only once per test run.
    override class func setUp() {
        getTestUsersFromYamlFiles()
    }

    /// Runs before eact test case.
    override func setUp() {
        super.setUp()

        continueAfterFailure = false

        app.launchArguments = launchArguments

        app.launchArguments.append("-disableAnimations")
        app.launchArguments.append("-skipTour")
        app.launchArguments.append("-toolbarSpotlightOff")
        app.launchArguments.append("-uiTests")
        app.launchArguments.append(contentsOf: ["-com.apple.CoreData.ConcurrencyDebug", "1"])
        app.launchArguments.append(contentsOf: ["-AppleLanguages", "(en)"])

        app.launchEnvironment[apiDomainKey] = dynamicDomain

        if humanVerificationStubs {
            app.launchEnvironment["HumanVerificationStubs"] = "1"
        } else if forceUpgradeStubs {
            app.launchEnvironment["ForceUpgradeStubs"] = "1"
        } else if extAccountNotSupportedStub {
            app.launchEnvironment["ExtAccountNotSupportedStub"] = "1"
        }
        app.launch()

        env = Environment.custom(dynamicDomain)
        quarkCommands = QuarkCommands(doh: env.doh)

        handleInterruption()
    }

    override func tearDown() {
        terminateApp()
        super.tearDown()
    }

    func handleInterruption() {
        let labels = [LocalString._skip_btn_title, "Allow Access to All Photos", "Select Photos...", "Don’t Allow", "Keep Current Selection",LocalString._send_anyway, LocalString._general_ok_action, LocalString._hide]
        /// Adds UI interruption monitor that queries all buttons and clicks if identifier is in the labels array. It is triggered when system alert interrupts the test execution.
        addUIMonitor(elementQueryToTap: XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons, identifiers: labels)
    }
    
    fileprivate func login(user: User) {
        loginRobot.loginUser(user)
    }

    private func loadUser(userKey: String) -> String {
        if let user = ProcessInfo.processInfo.environment[userKey] {
            return user
        } else {
            return getValueForKey(key: userKey, filename: credentialsFileName)!
        }
    }

    private func getValueForKey(key: String, filename: String) -> String? {
        var data = Data()
        var params = Dictionary<String, String>()

        /// Load files from "pm.ProtonMailUITests" bundle.
        guard let fileURL = Bundle(identifier: "pm.ProtonMailUITests")!.url(forResource: filename, withExtension: "plist") else {
            fatalError("Users credentials.plist file not found.")
        }
        do {
            data = try Data(contentsOf: fileURL)
            params = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! Dictionary<String, String>
        } catch {
            fatalError("Unable to parse credentials.plist file while running UI tests.")
        }
        return params[key]
    }
    
    private static func getYamlFiles(in folderURL: URL) -> [URL] {
        var files: [URL] = []

        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "user.yml" {
                    files.append(fileURL)
                }
            }
        }

        return files
    }
    
    private static func getTestUsersFromYamlFiles() {
        // Get "protonmail-ios/ProtonMail/" path to later locate "protonmail-ios/ProtonMail/TestData".
        let uiTestsFolderPath = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().path
        let folderUrl = URL(fileURLWithPath: "\(uiTestsFolderPath)/TestData")
        var userYamlFiles: [URL]

        userYamlFiles = getYamlFiles(in: folderUrl)
        
        XCTAssertTrue(userYamlFiles.count > 0, "Attempted to parse user.yml files from TestData repository but was not able to find any.")

        for file in userYamlFiles {
            do {
                if let data = try String(contentsOf: file).data(using: .utf8) {
                    let user = try YAMLDecoder().decode(TestUser.self, from: data)
                    users[user.user.name] = user
                }
            } catch {
                print("Error deserializing YAML: \(error.localizedDescription)")
            }
        }
    }
}

@available(iOS 16.0, *)
class FixtureAuthenticatedTestCase: BaseTestCase {

    var scenario: MailScenario { .qaMail001 }
    var plan: UserPlan { .mailpro2022 }
    var isSubscriptionIncluded: Bool { true }
    var user: User?

    override func setUp() {
        super.setUp()
        do {
            user = try createUserWithFixturesLoad(domain: dynamicDomain, plan: plan, scenario: scenario, isEnableEarlyAccess: false)
        }
        catch {
            XCTFail(error.localizedDescription)
        }

        login(user: user!)
    }

    override func tearDown() {
        do {
            try deleteUser(domain: dynamicDomain, user)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
        super.tearDown()
    }

    open override func record(_ issue: XCTIssue) {
        var myIssue = issue
        var issueDescription: String = "\n"
        issueDescription.append("User:")
        issueDescription.append("\n")
        issueDescription.append(user.debugDescription)
        issueDescription.append("\n\n")
        issueDescription.append("Failure:")
        issueDescription.append("\n\(myIssue.compactDescription)")

        myIssue.compactDescription = issueDescription
        super.record(myIssue)
    }
}

@available(iOS 16.0, *)
class NewFixtureAuthenticatedTestCase: BaseTestCase {

    var scenario: MailScenario { .trashOneMessage }
    var plan: UserPlan { .mailpro2022 }
    var isSubscriptionIncluded: Bool { true }
    var user: User?

    override func setUp() {
        super.setUp()
        do {
            user = try createUserWithiOSFixturesLoad(domain: dynamicDomain, plan: plan, scenario: scenario, isEnableEarlyAccess: false)
        }
        catch {
            XCTFail(error.localizedDescription)
        }

        login(user: user!)
    }

    override func tearDown() {
        do {
            try deleteUser(domain: dynamicDomain, user)
        }
        catch {
            XCTFail(error.localizedDescription)
        }
        super.tearDown()
    }

    open override func record(_ issue: XCTIssue) {
        var myIssue = issue
        var issueDescription: String = "\n"
        issueDescription.append("User:")
        issueDescription.append("\n")
        issueDescription.append(user.debugDescription)
        issueDescription.append("\n\n")
        issueDescription.append("Failure:")
        issueDescription.append("\n\(myIssue.compactDescription)")

        myIssue.compactDescription = issueDescription
        super.record(myIssue)
    }
}
