//
//  CoreDataTallyStore.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation
import CoreData

// http://redqueencoder.com/property-lists-and-user-defaults-in-swift/
/// A representation of a Type with internal property keys and values mapped to a NSDictionary that can be used in store
protocol TallyStoreType: Hashable {
    init?(dictionaryRepresentation:NSDictionary?)
    func dictionaryRepresentation() -> NSDictionary
}

class CoreDataTallyStore<StoreItem: TallyStoreType>: TallyStoreDelegate {
    
    typealias Item = StoreItem
    
    var stack = CoreDataStack()
    
    public typealias Root = CoreDataNode
    public var root: Root
    
    var context: NSManagedObjectContext {
        return stack.persistentContainer.viewContext
    }
    
    init() {
        self.root = CoreDataNode(node: Node<Item>.root, in: stack.persistentContainer.viewContext)
    }
    
    deinit {
        stack.saveContext()
    }
    
    public func incrementCount(for sequence: [Node<Item>]) {    
        root.incrementCount(for: [Node<Item>.root] + sequence)
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.itemProbabilities(after: [Node<Item>.root] + sequence)
    }
    
    func distributions(excluding excludedItems: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        
        let total: Double = root.childNodes.reduce(0.0, { partial, child in
            
            //let node = Node<Item>(dictionaryRepresentation: child.nodeDictionaryRepresentation!)!
            let node: Node<Item> = child.node()
            
            if node.isBoundaryOrRoot { return partial }
            if excludedItems.contains(node) { return partial }
            return partial + child.count
        })
        
        return root.childNodes.flatMap { child in
            
            //let node = Node<Item>(dictionaryRepresentation: child.nodeDictionaryRepresentation!)!
            let node: Node<Item> = child.node()
            
            if node.isBoundaryOrRoot { return nil }
            if excludedItems.contains(node) { return nil }
            
            let prob = child.count / total
            return (item: node, probability: prob)
        }
    }
}

enum NodeKey: String {
    case boundary = "boundary"
    case item = "item"
    case root = "root"
}

enum NodeBoundaryKey: String {
    case sequenceStart = "Value.SequenceStart"
    case sequenceEnd = "Value.SequenceEnd"
    case unseenLeadingItems = "Value.UnseenLeadingItems"
    case unseenTrailingItems = "Value.UnseenTrailingItems"
    
    var dictionaryRepresentation: [String: AnyObject] {
        return [NodeKey.boundary.rawValue: self.rawValue as AnyObject]
    }
}

extension Node where Item: TallyStoreType {
    
    static func boundryNode(from value: String) -> Node<Item>? {
        if let boundryType = NodeBoundaryKey(rawValue: value) {
            switch boundryType {
            case .sequenceEnd: return Node<Item>.sequenceEnd
            case .sequenceStart: return Node<Item>.sequenceStart
            case .unseenLeadingItems: return Node<Item>.unseenLeadingItems
            case .unseenTrailingItems: return Node<Item>.unseenTrailingItems
            }
        }
        return nil
    }
    
    init?(dictionaryRepresentation: NSDictionary) {
        
        guard let dictionary = dictionaryRepresentation as? [String: AnyObject],
            let keyRawValue = dictionary.keys.first,
            let key = NodeKey(rawValue: keyRawValue),
            let value = dictionary[keyRawValue]
            
        else {
            print("could not create node from dictionary")
            return nil
        }
        
        switch key {
        case .root:
            print("creting root from dictionary")
            self = Node<Item>.root
            
        case .boundary:
            if let boundaryValue = value as? String, let node = Node<Item>.boundryNode(from: boundaryValue) {
                print("creting boundary from dictionary")
                self = node
            }
            else { return nil }
            
        case .item:
            if let itemDictionary = value as? NSDictionary, let item = Item(dictionaryRepresentation: itemDictionary) {
                print("creting literal item from dictionary")
                self = Node<Item>.item(item)
            }
            else { return nil }
        }
    }
    
    func dictionaryRepresentation() -> NSDictionary {
        
        let dictionary: [String: AnyObject] = {
            switch self {
            // root
            case .root: return [NodeKey.root.rawValue: "root" as AnyObject]
                
            // boundary items
            case .sequenceEnd: return NodeBoundaryKey.sequenceEnd.dictionaryRepresentation
            case .sequenceStart: return NodeBoundaryKey.sequenceStart.dictionaryRepresentation
            case .unseenLeadingItems: return NodeBoundaryKey.unseenLeadingItems.dictionaryRepresentation
            case .unseenTrailingItems: return NodeBoundaryKey.unseenTrailingItems.dictionaryRepresentation
            
            // literal item
            case .item(let value):
                return [NodeKey.item.rawValue: value.dictionaryRepresentation()]
            }
        }()
        
        return dictionary as NSDictionary
    }
}

extension CoreDataNode {
    
    func node<Item: TallyStoreType>() -> Node<Item> {
        
        print("getting node from core data")
        print("self.nodeDictionaryRepresentation", self.nodeDictionaryRepresentation)
        
        guard let dictionary = self.nodeDictionaryRepresentation,
            let node = Node<Item>(dictionaryRepresentation: dictionary)
            else { fatalError("CoreDataNode internal inconsistancy") }
        
        return node
    }
    
    var childNodes: Set<CoreDataNode> {
        return self.children as? Set<CoreDataNode> ?? Set<CoreDataNode>()
    }
    
    convenience init<Item: TallyStoreType>(node: Node<Item> = Node<Item>.root, in context: NSManagedObjectContext) {
        
        self.init(context: context)
        self.id = UUID().uuidString
        self.nodeDictionaryRepresentation = node.dictionaryRepresentation()
        
        // TODO: Check to see if constructor is ever called with non-empty collection of children
        self.count = 0.0
        self.children = NSSet()
    }
    
    func incrementCount<Item: TallyStoreType>(for sequence: [Node<Item>]) {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first, let context = managedObjectContext {
            
            let child = childNodes.first(where: { node in
                return node.nodeDictionaryRepresentation == item.dictionaryRepresentation()
            }) ?? CoreDataNode(node: item, in: context)
            
            child.incrementCount(for: tail)
            self.addToChildren(child)
        }
        else {
            count += 1
        }
    }
    
    func itemProbabilities<Item: TallyStoreType>(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            if let child = childNodes.first(where: { node in
                return node.nodeDictionaryRepresentation == item.dictionaryRepresentation()
            }){
                return child.itemProbabilities(after: tail)
            }
        }
        else { // tail is empty
            let total: Double = childNodes.reduce(0.0, { partial, child in
                return partial + child.count
            })
            
            return childNodes.flatMap({ child in
                let prob = child.count / total
                if let item = Node<Item>(dictionaryRepresentation: child.nodeDictionaryRepresentation!) {
                    return (probability: prob, item: item)
                }
                return nil // TODO: Better way to deal with unlikely failure than return nil?
            })
        }
        return []
    }
}
