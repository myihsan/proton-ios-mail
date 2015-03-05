//
//  APIService.swift
//  ProtonMail
//
//
// Copyright 2015 ArcTouch, Inc.
// All rights reserved.
//
// This file, its contents, concepts, methods, behavior, and operation
// (collectively the "Software") are protected by trade secret, patent,
// and copyright laws. The use of the Software is governed by a license
// agreement. Disclosure of the Software to third parties, in any form,
// in whole or in part, is expressly prohibited except as authorized by
// the license agreement.
//

import CoreData
import Foundation

private let BaseURLString = "http://protonmail.xyz"

let APIServiceErrorDomain = NSError.protonMailErrorDomain(subdomain: "APIService")

let sharedAPIService = APIService()

class APIService {

    typealias CompletionBlock = (NSURLSessionDataTask!, Dictionary<String,AnyObject>?, NSError?) -> Void

    struct ErrorCode {
        static let badParameter = 1
        static let badPath = 2
        static let unableToParseResponse = 3
    }

    enum HTTPMethod {
        case DELETE
        case GET
        case POST
        case PUT
    }
    
    // MARK: - Internal variables
    
    internal typealias AFNetworkingFailureBlock = (NSURLSessionDataTask!, NSError!) -> Void
    internal typealias AFNetworkingSuccessBlock = (NSURLSessionDataTask!, AnyObject!) -> Void
    
    // MARK: - Private variables
    
    private let sessionManager: AFHTTPSessionManager
    
    // MARK: - Internal methods
    
    init() {
        sessionManager = AFHTTPSessionManager(baseURL: NSURL(string: BaseURLString)!)
        sessionManager.requestSerializer = AFJSONRequestSerializer() as AFHTTPRequestSerializer
        
        setupValueTransforms()
    }

    internal func afNetworkingBlocksForRequest(#method: HTTPMethod, path: String, parameters: AnyObject?, authenticated: Bool = true, completion: CompletionBlock?) -> (AFNetworkingSuccessBlock?, AFNetworkingFailureBlock?) {
        if let completion = completion {
            let failure: AFNetworkingFailureBlock = { task, error in
                completion(task, nil, error)
            }
            let success: AFNetworkingSuccessBlock = { task, responseObject in
                if let responseDictionary = responseObject as? Dictionary<String, AnyObject> {
                    if authenticated && responseDictionary["code"] as? Int == 401 {
                        AuthCredential.expireOrClear()
                        self.request(method: method, path: path, parameters: parameters, authenticated: authenticated, completion: completion)
                    } else {
                        completion(task, responseDictionary, nil)
                    }
                } else if responseObject == nil {
                    completion(task, [:], nil)
                } else {
                    completion(task, nil, NSError.unableToParseResponse(responseObject))
                }
            }
            
            return (success, failure)
        }
        
        return (nil, nil)
    }
    
    internal func completionWrapperParseCompletion(completion: CompletionBlock?, forKey key: String) -> CompletionBlock? {
        if completion == nil {
            return nil
        }
        
        return { task, response, error in
            if error != nil {
                completion?(task, nil, error)
            } else {
                if let parsedResponse = response?[key] as? Dictionary<String, AnyObject> {
                    completion?(task, parsedResponse, nil)
                } else {
                    completion?(task, nil, NSError.unableToParseResponse(response))
                }
            }
        }
    }
    
    internal func fetchAuthCredential(#completion: AuthCredentialBlock) {
        if let credential = AuthCredential.fetchFromKeychain() {
            if !credential.isExpired {
                self.sessionManager.requestSerializer.setAuthorizationHeaderFieldWithCredential(credential)
                NSLog("credential: \(credential)")
                completion(credential, nil)
            } else {
                authRefresh { (authCredential, error) -> Void in
                    if error != nil && error!.domain == APIServiceErrorDomain && error!.code == APIService.AuthErrorCode.invalidGrant {
                        AuthCredential.clearFromKeychain()
                        self.fetchAuthCredential(completion: completion)
                    } else {
                        completion(authCredential, error)
                    }
                }
            }
        } else {
            let username = sharedUserDataService.username ?? ""
            let password = sharedUserDataService.password ?? ""
            
            let completionWrapper: AuthCredentialBlock = { authCredential, error in
                if error != nil && error!.domain == APIServiceErrorDomain && error!.code == AuthErrorCode.credentialInvalid {
                    sharedUserDataService.signOut(true)
                }
            }
            
            authAuth(username: username, password: password, completion: completionWrapper)
        }
    }
    
    // MARK: - Request methods
    
    /// downloadTask returns the download task for use with UIProgressView+AFNetworking
    internal func download(#path: String, destinationDirectoryURL: NSURL, downloadTask: ((NSURLSessionDownloadTask) -> Void)?, completion: ((NSURLResponse?, NSURL?, NSError?) -> Void)?) {
        AuthCredential.expireOrClear()
        fetchAuthCredential() { _, error in
            if error == nil {
                if let url = NSURL(string: path, relativeToURL: self.sessionManager.baseURL) {
                    let request = NSURLRequest(URL: url)
                    
                    if let sessionDownloadTask = self.sessionManager.downloadTaskWithRequest(
                        request,
                        progress: nil,
                        destination: { (targetURL, response) -> NSURL! in
                            return destinationDirectoryURL.URLByAppendingPathComponent(response.suggestedFilename!)
                        },
                        completionHandler: completion) {
                            downloadTask?(sessionDownloadTask)
                    }
                } else {
                    completion?(nil, nil, NSError.badPath(path))
                    return
                }
            } else {
                completion?(nil, nil, error)
            }
        }
    }
    
    internal func request(#method: HTTPMethod, path: String, parameters: AnyObject?, authenticated: Bool = true, completion: CompletionBlock?) {
        let authBlock: AuthCredentialBlock = { _, error in
            if error == nil {
                let (successBlock, failureBlock) = self.afNetworkingBlocksForRequest(method: method, path: path, parameters: parameters, authenticated: authenticated, completion: completion)
                
                switch(method) {
                case .DELETE:
                    self.sessionManager.DELETE(path, parameters: parameters, success: successBlock, failure: failureBlock)
                case .POST:
                    self.sessionManager.POST(path, parameters: parameters, success: successBlock, failure: failureBlock)
                case .PUT:
                    self.sessionManager.PUT(path, parameters: parameters, success: successBlock, failure: failureBlock)
                default:
                    self.sessionManager.GET(path, parameters: parameters, success: successBlock, failure: failureBlock)
                }
            } else {
                completion?(nil, nil, error)
            }
        }

        if authenticated {
            fetchAuthCredential(completion: authBlock)
        } else {
            authBlock(nil, nil)
        }
    }
    
    // MARK: - Private methods
    
    private func setupValueTransforms() {
        let boolTransformer = GRTValueTransformer.reversibleTransformerWithBlock { (value) -> AnyObject! in
            if let bool = value as? NSString {
                return bool.boolValue
            } else if let bool = value as? Bool {
                return bool
            }
            
            return nil
        }
        
        NSValueTransformer.setValueTransformer(boolTransformer, forName: "BoolTransformer")
        
        let dateTransformer = GRTValueTransformer.reversibleTransformerWithBlock { (value) -> AnyObject! in
            if let timeString = value as? NSString {
                let time = timeString.doubleValue as NSTimeInterval
                if time != 0 {
                    return time.asDate()
                }
            } else if let date = value as? NSDate {
                return date.timeIntervalSince1970
            }
            
            return nil
        }
        
        NSValueTransformer.setValueTransformer(dateTransformer, forName: "DateTransformer")

        let numberTransformer = GRTValueTransformer.reversibleTransformerWithBlock { (value) -> AnyObject! in
            if let number = value as? String {
                return number.toInt() ?? 0 as NSNumber
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
            
            return nil
        }
        
        NSValueTransformer.setValueTransformer(numberTransformer, forName: "NumberTransformer")

        let tagTransformer = GRTValueTransformer.reversibleTransformerWithBlock { (value) -> AnyObject! in
            if let tag = value as? String {
                return tag.rangeOfString(Message.Constants.starredTag) != nil
            }
            
            return nil
        }
        
        NSValueTransformer.setValueTransformer(tagTransformer, forName: "TagTransformer")
    }
}

// MARK: - NSError APIService extension

extension NSError {
    
    class func apiServiceError(#code: Int, localizedDescription: String, localizedFailureReason: String?, localizedRecoverySuggestion: String? = nil) -> NSError {
        return NSError(
            domain: APIServiceErrorDomain,
            code: code,
            localizedDescription: localizedDescription,
            localizedFailureReason: localizedFailureReason,
            localizedRecoverySuggestion: localizedRecoverySuggestion)
    }
    
    class func badParameter(parameter: AnyObject?) -> NSError {
        return apiServiceError(
            code: APIService.ErrorCode.badParameter,
            localizedDescription: NSLocalizedString("Bad parameter"),
            localizedFailureReason: NSLocalizedString("Bad parameter: \(parameter)"))
    }
    
    class func badPath(path: String) -> NSError {
        return apiServiceError(
            code: APIService.ErrorCode.badPath,
            localizedDescription: NSLocalizedString("Bad path"),
            localizedFailureReason: NSLocalizedString("Unable to construct a valid URL with the following path: \(path)"))
    }
    
    class func unableToParseResponse(response: AnyObject?) -> NSError {
        let noObject = NSLocalizedString("<no object>")
        
        return apiServiceError(
            code: APIService.ErrorCode.unableToParseResponse,
            localizedDescription: NSLocalizedString("Unable to parse response"),
            localizedFailureReason: NSLocalizedString("Unable to parse the response object:\n\(response ?? noObject)"))
    }
}
