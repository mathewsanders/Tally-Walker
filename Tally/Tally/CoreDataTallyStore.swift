//
//  CoreDataTallyStore.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation
import CoreData

class CoreDataTallyStore<Item>: TallyStoreType where Item: Hashable, Item: LosslessDictionaryConvertible {
        
    var stack = CoreDataStack()
    private var root: CoreDataNodeWrapper<Item>
    
    init() {
        self.root = CoreDataNodeWrapper(in: stack.persistentContainer.viewContext)
    }
    
    deinit {
        stack.saveContext()
    }
    
    // MARK: TallyStoreType
    
    public func incrementCount(for sequence: [Node<Item>]) {    
        root.incrementCount(for: [Node<Item>.root] + sequence)
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.itemProbabilities(after: [Node<Item>.root] + sequence)
    }
    
    func distributions(excluding excludedItems: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.distributions(excluding: excludedItems)
    }
}

// MARK: - TallyStoreNodeType

fileprivate final class CoreDataNodeWrapper<Item>: TallyStoreNodeType where Item: Hashable, Item: LosslessDictionaryConvertible {
    
    private var _node: CoreDataNode
    private var context: NSManagedObjectContext
    
    init(in context: NSManagedObjectContext) {
        self._node = CoreDataNode(node: Node<Item>.root, in: context)
        self.context = context
    }
    
    init(node: CoreDataNode, in context: NSManagedObjectContext) {
        self._node = node
        self.context = context
    }
    
    convenience init(item: Node<Item>, in context: NSManagedObjectContext) {
        let node = CoreDataNode(node: item, in: context)
        self.init(node: node, in: context)
    }
    
    internal var node: Node<Item> {
        
        guard let dictionary = _node.nodeDictionaryRepresentation,
            let nodeFromDictionary = Node<Item>(dictionaryRepresentation: dictionary)
            else { fatalError("CoreDataNode internal inconsistancy") }
        
        return nodeFromDictionary
    }
    
    internal var count: Double {
        get { return _node.count }
        set { _node.count = newValue }
    }
    
    public func addChild(_ child: CoreDataNodeWrapper<Item>) {
        _node.addToChildren(child._node)
    }
    
    public var childNodes: [CoreDataNodeWrapper<Item>]{
        return Array(_node.childrenSet.map{ return CoreDataNodeWrapper(node: $0, in: context) })
    }
    
    public func childNode(with item: Node<Item>) -> CoreDataNodeWrapper<Item> {
        return childNodes.first(where: { wrapper in
            return wrapper.node == item
        }) ?? CoreDataNodeWrapper(item: item, in: context)
    }
}

// MARK: - CoreDataNode Helper

fileprivate extension CoreDataNode {
    
    var childrenSet: Set<CoreDataNode> {
        return (children as? Set<CoreDataNode> ?? Set<CoreDataNode>())
    }
    
    convenience init<Item: LosslessDictionaryConvertible>(node: Node<Item>, in context: NSManagedObjectContext) {
        
        self.init(context: context)
        self.id = UUID().uuidString // TODO: Remove id from model
        self.nodeDictionaryRepresentation = node.dictionaryRepresentation()
        
        self.count = 0.0
        self.children = NSSet() // TODO: Check to see if children can be set as nil
    }
}

// MARK: - CoreDataStack

internal class CoreDataStack {
    
    lazy var persistentContainer: NSPersistentContainer = {
        
        // Bundle(identifier: "com.mathewsanders.Tally")
        let bundle = Bundle(for: CoreDataStack.self) // check this works as expected in a module
        
        // TODO: Investigate option for creating model in code rather than as a resource
        // especially if this allows for the NSManagedObject subclasses to be automatically generated
        guard let modelUrl = bundle.url(forResource: "TallyStoreModel", withExtension: "momd"),
            let mom = NSManagedObjectModel(contentsOf: modelUrl)
            else { fatalError("Unresolved error") }
        
        let container = NSPersistentContainer(name: "TallyStoreModel", managedObjectModel: mom)
        
        container.loadPersistentStores{ (storeDescription, error) in
            if let error = error { fatalError("Unresolved error \(error)") } // TODO: Manage error
        }
        return container
    }()
    
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch let error as NSError { fatalError("Unresolved error \(error.description)") } // TODO: Manage error
        }
    }
}

// MARK: - LosslessDictionaryConvertible & Node extension

/// A representation of a Type with internal property keys and values mapped to a NSDictionary that can be used in store
protocol LosslessDictionaryConvertible {
    init?(dictionaryRepresentation: NSDictionary)
    func dictionaryRepresentation() -> NSDictionary
}

fileprivate enum NodeKey: String {
    case boundary = "Node.Boundary"
    case item = "Note.Item"
    case root = "Node.Root"
    
    var dictionaryKey: String {
        return self.rawValue
    }
}

fileprivate enum NodeBoundaryKey: String {
    case sequenceStart = "SequenceStart"
    case sequenceEnd = "SequenceEnd"
    case unseenLeadingItems = "UnseenLeadingItems"
    case unseenTrailingItems = "UnseenTrailingItems"
    
    var dictionaryRepresentation: [String: AnyObject] {
        return [NodeKey.boundary.rawValue: self.rawValue as AnyObject]
    }
}

fileprivate extension Node where Item: LosslessDictionaryConvertible {
    
    static func boundaryNode(from value: String) -> Node<Item>? {
        
        guard let boundaryType = NodeBoundaryKey(rawValue: value)
            else { return nil }
        
        switch boundaryType {
        case .sequenceEnd: return Node<Item>.sequenceEnd
        case .sequenceStart: return Node<Item>.sequenceStart
        case .unseenLeadingItems: return Node<Item>.unseenLeadingItems
        case .unseenTrailingItems: return Node<Item>.unseenTrailingItems
        }
    }
    
    init?(dictionaryRepresentation: NSDictionary) {
        
        guard let dictionary = dictionaryRepresentation as? [String: AnyObject],
            let keyRawValue = dictionary.keys.first,
            let key = NodeKey(rawValue: keyRawValue),
            let value = dictionary[keyRawValue]
            else { return nil }
        
        switch key {
        case .root:
            self = Node<Item>.root
            
        case .boundary:
            guard let boundaryValue = value as? String,
                let node = Node<Item>.boundaryNode(from: boundaryValue)
                else { return nil }
            self = node
            
        case .item:
            guard let itemDictionary = value as? NSDictionary,
                let item = Item(dictionaryRepresentation: itemDictionary)
                else { return nil }
            self = Node<Item>.item(item)
        }
    }
    
    func dictionaryRepresentation() -> NSDictionary {
        
        let dictionary: [String: AnyObject] = {
            switch self {
            // root
            case .root: return [NodeKey.root.dictionaryKey: "root" as AnyObject]
                
            // boundary items
            case .sequenceEnd: return NodeBoundaryKey.sequenceEnd.dictionaryRepresentation
            case .sequenceStart: return NodeBoundaryKey.sequenceStart.dictionaryRepresentation
            case .unseenLeadingItems: return NodeBoundaryKey.unseenLeadingItems.dictionaryRepresentation
            case .unseenTrailingItems: return NodeBoundaryKey.unseenTrailingItems.dictionaryRepresentation
                
            // literal item
            case .item(let value):
                return [NodeKey.item.dictionaryKey: value.dictionaryRepresentation()]
            }
        }()
        
        return dictionary as NSDictionary
    }
}
