//
//  CoreDataNode+CoreDataProperties.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation
import CoreData
//import

extension CoreDataNode {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataNode> {
        return NSFetchRequest<CoreDataNode>(entityName: "CoreDataNode")
    }

    @NSManaged public var count: Double
    @NSManaged public var id: String
    @NSManaged public var nodeDictionaryRepresentation: NSDictionary
    @NSManaged public var children: Set<CoreDataNode>
    @NSManaged public var parent: CoreDataNode?

}

// MARK: Generated accessors for children
extension CoreDataNode {

    @objc(addChildrenObject:)
    @NSManaged public func addToChildren(_ value: CoreDataNode)

    @objc(removeChildrenObject:)
    @NSManaged public func removeFromChildren(_ value: CoreDataNode)

    @objc(addChildren:)
    @NSManaged public func addToChildren(_ values: NSSet)

    @objc(removeChildren:)
    @NSManaged public func removeFromChildren(_ values: NSSet)

}
