//
//  ContactExtension.swift
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

extension Contact {

    struct Attributes {
        static let entityName = "Contact"
        static let contactID = "contactID"
        static let email = "email"
        static let name = "name"
    }

    // MARK: - Public methods
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: NSEntityDescription.entityForName(Attributes.entityName, inManagedObjectContext: context)!, insertIntoManagedObjectContext: context)
    }
    
    // MARK: - Private methods
    
    override func awakeFromInsert() {
        super.awakeFromInsert()
        
        // Set nil string attributes to ""
        for (_, attribute) in entity.attributesByName as [String : NSAttributeDescription] {
            if attribute.attributeType == .StringAttributeType {
                if valueForKey(attribute.name) == nil {
                    setValue("", forKey: attribute.name)
                }
            }
        }
    }
}
