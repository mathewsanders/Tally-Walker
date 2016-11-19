//
//  CoreDataTallyStore.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation
import CoreData

public class CoreDataTallyStore<Item>: TallyStoreType where Item: Hashable, Item: LosslessDictionaryConvertible {
        
    private var stack: CoreDataStack
    private var root: CoreDataNodeWrapper<Item>
    
    static func stackIdentifier(named name: String) -> String {
        return "Tally.CoreDataStore." + name
    }
    
    public init(named name: String = "DefaultStore", restoreFrom existingStore: URL? = nil, inMemory: Bool = false) {
        let identifier = CoreDataTallyStore.stackIdentifier(named: name)
        self.stack = CoreDataStack(identifier: identifier, existingStore: existingStore, inMemory: inMemory)
        self.root = stack.getRoot()
    }
    
    public func save() {
        stack.saveContext()
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
    
    public func distributions(excluding excludedItems: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.distributions(excluding: excludedItems)
    }
}

// MARK: - TallyStoreNodeType

fileprivate final class CoreDataNodeWrapper<Item>: TallyStoreNodeType where Item: Hashable, Item: LosslessDictionaryConvertible {
    
    fileprivate var _node: CoreDataNode
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
    
    // profiling is showing that this is a bottleneck, especially the initializer
    lazy internal var node: Node<Item> = {
        guard let dictionary = self._node.nodeDictionaryRepresentation, // this is grabbing the transformable property
            let nodeFromDictionary = Node<Item>(dictionaryRepresentation: dictionary)
            else { fatalError("CoreDataNode internal inconsistancy") }
        
        return nodeFromDictionary
    }()
    
    internal var count: Double {
        get { return _node.count }
        set { _node.count = newValue }
    }
    
//    public var childNodes: [CoreDataNodeWrapper<Item>]{
//        guard let childrenSet = _node.children as? Set<CoreDataNode> else { return [] }
//        return Array(childrenSet.map{ return CoreDataNodeWrapper(node: $0, in: context) })
//    }
    
    public var childNodes: AnySequence<CoreDataNodeWrapper<Item>> {
        guard let childrenSet = _node.children as? Set<CoreDataNode> else {
            let empty: [CoreDataNodeWrapper<Item>] = []
            return AnySequence(empty)
        }
        
        return AnySequence(childrenSet.lazy.map{ return CoreDataNodeWrapper(node: $0, in: self.context) })
    }
    
    public func findChildNode(with item: Node<Item>) -> CoreDataNodeWrapper<Item>? {
        return childNodes.first(where: { wrapper in
            return wrapper.node == item
        })
    }
    
    public func makeChildNode(with item: Node<Item>) -> CoreDataNodeWrapper<Item> {
        let child = CoreDataNodeWrapper(item: item, in: context)
        _node.addToChildren(child._node)        
        return child
    }
}

// MARK: - CoreDataNode Helper

fileprivate extension CoreDataNode {
    
    // TODO: Update schema so that root, and boundary items are directly represented, 
    // and only an item node is captured by the transferable property
    convenience init<Item: LosslessDictionaryConvertible>(node: Node<Item>, in context: NSManagedObjectContext) {
        self.init(context: context)
        self.nodeDictionaryRepresentation = node.dictionaryRepresentation()
    }
}

// MARK: - CoreDataStack

internal class CoreDataStack {
    
    let persistentContainer: NSPersistentContainer
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    // TODO: Investigate having a read-only store for `itemProbabilities` and `distributions`
    init(identifier containerName: String, existingStore storeUrl: URL? = nil, inMemory: Bool = false) {
        
        let bundle = Bundle(for: CoreDataStack.self) // check this works as expected in a module
        
        // TODO: Investigate option for creating model in code rather than as a resource
        // especially if this allows for the NSManagedObject subclasses to be automatically generated
        guard let modelUrl = bundle.url(forResource: "TallyStoreModel", withExtension: "momd"),
            let mom = NSManagedObjectModel(contentsOf: modelUrl)
            else { fatalError("Unresolved error") }
        
        persistentContainer = NSPersistentContainer(name: containerName, managedObjectModel: mom)
        
        if inMemory {
            print("Warning: Core Data using NSInMemoryStoreType, changes will not persist, use for testing only")
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            persistentContainer.persistentStoreDescriptions = [description]
        }
        
        if let storeUrl = storeUrl {
            // TODO: Should validate if the resource at the URL is a sqlite resource
            // and that it has an approrpiate model
            let description = NSPersistentStoreDescription()
            description.url = storeUrl
            persistentContainer.persistentStoreDescriptions = [description]
            
            // TODO: Review default options 
            // https://alastairs-place.net/blog/2013/04/17/why-core-data-is-a-bad-idea/
            let sqlitePragmas = description.sqlitePragmas
            print("sqlitePragmas:")
            print(sqlitePragmas)
        }
        
        persistentContainer.loadPersistentStores{ (storeDescription, error) in
            print(storeDescription)
            if let error = error { fatalError("Unresolved error \(error)") } // TODO: Manage error
        }
    }
    
    private func fetchExistingRoot<Item>() -> CoreDataNodeWrapper<Item>? where Item: Hashable, Item: LosslessDictionaryConvertible {
        
        // look for root by fetching node with no parent
        let request: NSFetchRequest<CoreDataNode> = CoreDataNode.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "parent = nil")
        
        do {
            guard let rootItem = try context.fetch(request).first else { return nil }
            return CoreDataNodeWrapper<Item>(node: rootItem, in: context)
        }
        catch { return nil }
    }
    
    fileprivate func getRoot<Item>() -> CoreDataNodeWrapper<Item> where Item: Hashable, Item: LosslessDictionaryConvertible {
        return fetchExistingRoot() ?? CoreDataNodeWrapper<Item>(in: context)
    }
    
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch let error as NSError { fatalError("Unresolved error \(error.description)") } // TODO: Manage error
        }
        else {
            print("no changes to save")
        }
    }
}

// MARK: - LosslessDictionaryConvertible & Node extension

/// A representation of a Type with internal property keys and values mapped to a NSDictionary that can be used in store
public protocol LosslessDictionaryConvertible {
    init?(dictionaryRepresentation: NSDictionary)
    func dictionaryRepresentation() -> NSDictionary
}

public protocol LosslessTextConvertible: LosslessDictionaryConvertible {
    init?(_ text: String)
}

// TODO: Research if `type(of: self)` is a possible bottleneck
public extension LosslessDictionaryConvertible {
    public static var losslessDictionaryKey: String {
        let type = type(of: self)
        return "\(type)"
        //return "LosslessDictionaryConvertible.key"
    }
}

public extension LosslessTextConvertible {
    
    init?(dictionaryRepresentation: NSDictionary) {
        guard let value = dictionaryRepresentation[Self.losslessDictionaryKey] as? Self else {
            return nil
        }
        self = value
    }
    
    func dictionaryRepresentation() -> NSDictionary {
        let dict = [Self.losslessDictionaryKey: self]
        return dict as NSDictionary
    }
}

// Attempt to optimize this
// http://stackoverflow.com/a/32421787/1060154
fileprivate enum NodeKey: RawRepresentable {
    
    typealias RawValue = String
    
    case root
    case boundary
    case item
    
    static let hashToRaw: [String] = [
        "Node.Root",
        "Node.Boundary",
        "Node.Item"
    ]
    
    static let rawToEnum: [String: NodeKey] = [
        "Node.Root": .root,
        "Node.Boundary": .boundary,
        "Node.Item": .item
    ]
    
    var rawValue: String {
        return NodeKey.hashToRaw[hashValue]
    }
    
    init?(rawValue: String) {
        if let nodeKey = NodeKey.rawToEnum[rawValue] {
            self = nodeKey
        }
        else {
            return nil
        }
    }
    
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
