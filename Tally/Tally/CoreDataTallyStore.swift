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
    
    public init(named name: String = "DefaultStore", storeUrl: URL? = nil, inMemory: Bool = false) {
        let identifier = CoreDataTallyStore.stackIdentifier(named: name)
        self.stack = CoreDataStack(identifier: identifier, storeUrl: storeUrl, inMemory: inMemory)
        self.root = stack.getRoot(with: identifier)
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
    
    public var childNodes: [CoreDataNodeWrapper<Item>]{
        guard let childrenSet = _node.children as? Set<CoreDataNode> else { return [] }
        return Array(childrenSet.map{ return CoreDataNodeWrapper(node: $0, in: context) })
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
    
    convenience init<Item: LosslessDictionaryConvertible>(node: Node<Item>, in context: NSManagedObjectContext) {
        self.init(context: context)
        self.nodeDictionaryRepresentation = node.dictionaryRepresentation()
    }
}

// MARK: - CoreDataStack

internal class CoreDataStack {
    
    var persistentContainer: NSPersistentContainer
    
    var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    init(identifier containerName: String, storeUrl: URL? = nil, inMemory: Bool = false) {
        
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
            let description = NSPersistentStoreDescription(url: storeUrl)
            persistentContainer.persistentStoreDescriptions = [description]
        }
        
        persistentContainer.loadPersistentStores{ (storeDescription, error) in
            print(storeDescription)
            if let error = error { fatalError("Unresolved error \(error)") } // TODO: Manage error
        }
    }
    
    enum RootLoadError: Error {
        case noRootUri
        case castError
    }
    
    func rootNodeKey(with identifier: String) -> String {
        return "Tally.Root.Uri." + identifier
    }
    
    private func loadRootFromUserDefaults<Item>(withKey key: String) throws -> CoreDataNodeWrapper<Item> where Item: Hashable, Item: LosslessDictionaryConvertible {
        
        guard let uri = UserDefaults.standard.url(forKey: key),
            let moid = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri)
            else { throw RootLoadError.noRootUri }
        
        guard let rootItem = try context.existingObject(with: moid) as? CoreDataNode
            else { throw RootLoadError.castError }
        
        return CoreDataNodeWrapper<Item>(node: rootItem, in: context)
    }
    
    fileprivate func getRoot<Item>(with identifier: String) -> CoreDataNodeWrapper<Item> where Item: Hashable, Item: LosslessDictionaryConvertible {
        
        let rootNodeKey = self.rootNodeKey(with: identifier)
        
        do { // load from root.uri
            let existingRoot: CoreDataNodeWrapper<Item> = try loadRootFromUserDefaults(withKey: rootNodeKey)
            return existingRoot
        }
        catch { // couldn't find root, so will create a new one
            let newRoot = CoreDataNodeWrapper<Item>(in: context)
            saveContext() // so that objectID is stable
            UserDefaults.standard.set(newRoot._node.objectID.uriRepresentation(), forKey: rootNodeKey)
            return newRoot
        }
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

public extension LosslessDictionaryConvertible {
    public static var losslessDictionaryKey: String {
        let type = type(of: self)
        return "\(type)"
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

fileprivate enum NodeKey: String {
    case boundary = "Node.Boundary"
    case item = "Node.Item"
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
