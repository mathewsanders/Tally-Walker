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
    private var backgroundRoot: CoreDataNodeWrapper<Item>
    
    static func stackIdentifier(named name: String) -> String {
        return "Tally.CoreDataStore." + name
    }
    
    public init(named name: String = "DefaultStore", fillFrom archivedStore: URL? = nil, inMemory: Bool = false) {
        let identifier = CoreDataTallyStore.stackIdentifier(named: name)
        
        self.stack = CoreDataStack(identifier: identifier, fromArchive: archivedStore, inMemory: inMemory)
        self.root = stack.getRoot(from: stack.mainContext)
        self.backgroundRoot = stack.getRoot(from: stack.backgroundContext)
    }
    
    deinit {
        self.stack.save(context: stack.mainContext)
    }
    
    // TODO: Explore if `migratePersistentStore` is needed to extract a store to be later imported
    // Also check to see if -shm and -wal files need to be included.
    public func archive(to name: String) throws {
        
        if let currentStore = self.stack.persistentContainer.persistentStoreCoordinator.persistentStores.last,
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            
            let newLocation = documentDirectory.appendingPathComponent(name).appendingPathExtension("sqlite")
                
            try self.stack.persistentContainer.persistentStoreCoordinator.migratePersistentStore(currentStore, to: newLocation, options: nil, withType: NSSQLiteStoreType)
        }
    }
    
    // MARK: TallyStoreType
    
    public func incrementCount(for sequence: [Node<Item>]) {
        stack.mainContext.refreshAllObjects()
        
        stack.backgroundContext.perform {
            self.backgroundRoot.incrementCount(for: [Node<Item>.root] + sequence)
            self.stack.save(context: self.stack.backgroundContext)
        }
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.itemProbabilities(after: [Node<Item>.root] + sequence)
    }
    
    public func distributions(excluding excludedItems: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.distributions(excluding: excludedItems)
    }
}

// MARK: - TallyStoreNodeType

// can not extend NSManangedOjbect as a generic type, so using this as a wrapper
fileprivate struct CoreDataNodeWrapper<Item>: TallyStoreNodeType where Item: Hashable, Item: LosslessDictionaryConvertible {
    
    fileprivate var _node: CoreDataNode
    private var context: NSManagedObjectContext
    
    init(node: CoreDataNode, in context: NSManagedObjectContext) {
        self._node = node
        self.context = context
    }
    
    init(in context: NSManagedObjectContext) {
        let root = CoreDataNode(node: Node<Item>.root, in: context)
        root.count = 1.0
        self.init(node: root, in: context)
    }
    
    init(item: Node<Item>, in context: NSManagedObjectContext) {
        let node = CoreDataNode(node: item, in: context)
        self.init(node: node, in: context)
    }
    
    // profiling is showing that this is a bottleneck, especially the initializer
    internal var node: Node<Item> {
        
        switch self._node.itemType {
            
        case .root: return Node<Item>.root
        case .boundaryUnseenLeadingItems: return Node<Item>.unseenLeadingItems
        case .boundaryUnseenTrailingItems: return Node<Item>.unseenTrailingItems
        case .boundarySequenceStart: return Node<Item>.sequenceStart
        case .boundarySequenceEnd: return Node<Item>.sequenceEnd
            
        case .item:
            // this is grabbing the transformable property
            guard let dictionary = self._node.item?.itemDictionaryRepresentation,
                let nodeFromDictionary = Node<Item>(itemDictionaryRepresentation: dictionary)
                else { fatalError("CoreDataNode internal inconsistancy") }
            
            return nodeFromDictionary
        }
    }
    
    internal var count: Double {
        get { return _node.count }
        set { _node.count = newValue }
    }
    
    public var childNodes: AnySequence<CoreDataNodeWrapper<Item>> {
        guard let childrenSet = _node.children as? Set<CoreDataNode> else {
            let empty: [CoreDataNodeWrapper<Item>] = []
            return AnySequence(empty)
        }
        return AnySequence(childrenSet.lazy.map{ return CoreDataNodeWrapper(node: $0, in: self.context) })
    }
    
    // TODO: Investigate if node literal values could be stored independently 
    // (which would decrease store size), and after retrieving that literal item instance,
    // check to see if `parents` includes `self`.
    public func findChildNode(with item: Node<Item>) -> CoreDataNodeWrapper<Item>? {
        
        
        
        return childNodes.first(where: { childWrapper in
            return childWrapper.item(is: item)
        })
    }
    
    // nodeType is cheaper check than unrwapping node, so do this first
    private func item(is node: Node<Item>) -> Bool {
        return self._node.itemType == node.itemType && node == self.node
    }
    
    public func makeChildNode(with item: Node<Item>) -> CoreDataNodeWrapper<Item> {
        let child = CoreDataNodeWrapper(item: item, in: context)
        //_node.addToChildren(child._node)
        child._node.parent = _node
        return child
    }
}

// MARK: - CoreDataNode Helper

// TODO: Review if this is a bottleneck
// http://stackoverflow.com/a/32421787/1060154
enum CoreDataItemType: Int {
    case root = 0
    case boundaryUnseenTrailingItems
    case boundaryUnseenLeadingItems
    case boundarySequenceStart
    case boundarySequenceEnd
    case item
}

fileprivate extension CoreDataLiteralItem {
    
}

fileprivate extension CoreDataNode {
    
    var itemType: CoreDataItemType {
        set {
            self.itemTypeInt16Value = Int16(exactly: newValue.rawValue)!
        }
        get {
            guard let intFromInt16 = Int(exactly: self.itemTypeInt16Value),
                let type = CoreDataItemType(rawValue: intFromInt16) else {
                    fatalError("CoreDataNodeType internal representation inconsistancy")
            }
            return type
        }
    }
    
    convenience init<Item: LosslessDictionaryConvertible>(node: Node<Item>, in context: NSManagedObjectContext) {
        self.init(context: context)
        
        self.itemType = node.itemType
        if case .item = node.itemType {
            
            // TODO, if the item is a scalar type, the node could have properties to represent it directly
            let coreDataItem = CoreDataLiteralItem(context: context)
            coreDataItem.itemDictionaryRepresentation = node.itemDictionaryRepresentation()
        
            self.item = coreDataItem
            
        }
    }
}

// MARK: - CoreDataStack

internal class CoreDataStack {
    
    let persistentContainer: NSPersistentContainer
    
    lazy var mainContext: NSManagedObjectContext = {
        let context = self.persistentContainer.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }()
    
    lazy var backgroundContext: NSManagedObjectContext = {
        let context = self.persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }()
    
    init(identifier storeName: String, fromArchive archivedStore: URL? = nil, inMemory: Bool = false) {
        
        let bundle = Bundle(for: CoreDataStack.self) // check this works as expected in a module
        
        // TODO: Investigate option for creating model in code rather than as a resource
        // especially if this allows for the NSManagedObject subclasses to be automatically generated
        guard let modelUrl = bundle.url(forResource: "TallyStoreModel", withExtension: "momd"),
            let mom = NSManagedObjectModel(contentsOf: modelUrl)
            else { fatalError("Unresolved error") }
        
        persistentContainer = NSPersistentContainer(name: storeName, managedObjectModel: mom)
        
        if inMemory {
            print("Warning: Core Data using NSInMemoryStoreType, changes will not persist, use for testing only")
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            persistentContainer.persistentStoreDescriptions = [description]
        }
        
        if let storeUrl = archivedStore {
            // TODO: Should validate if the resource at the URL is a sqlite resource
            // and that it has an approrpiate model
            
            let documentStoreUrl = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(storeName).appendingPathExtension("sqlite")
            
            if !FileManager.default.fileExists(atPath: documentStoreUrl.path) {
                do {
                    try FileManager.default.copyItem(at: storeUrl, to: documentStoreUrl)
                }
                catch let error as NSError {
                    fatalError(error.description)
                }
            }
            
            let description = NSPersistentStoreDescription()
            description.url = documentStoreUrl
            persistentContainer.persistentStoreDescriptions = [description]
        }
        
        persistentContainer.loadPersistentStores{ (storeDescription, error) in
            print(storeDescription)
            if let error = error { fatalError("Unresolved error \(error)") } // TODO: Manage error
        }
    }
    
    private func fetchExistingRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item>? where Item: Hashable, Item: LosslessDictionaryConvertible {
        
        // look for root by fetching node with no parent
        let request: NSFetchRequest<CoreDataNode> = CoreDataNode.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "parent = nil")
        request.relationshipKeyPathsForPrefetching = ["children"]
        
        do {
            let rootItems = try context.fetch(request)
            guard rootItems.count == 1,
                let rootItem = rootItems.first
                else { return nil }
            
            return CoreDataNodeWrapper<Item>(node: rootItem, in: context)
        }
        catch { return nil }
    }
    
    fileprivate func getRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item> where Item: Hashable, Item: LosslessDictionaryConvertible {
        return fetchExistingRoot(from: context) ?? CoreDataNodeWrapper<Item>(in: context)
    }
    
    func save(context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch let error as NSError { fatalError("Unresolved error \(error.description)") } // TODO: Manage error
        }
    }
}

// MARK: - LosslessDictionaryConvertible & Node extension

fileprivate struct CoreDataTallyStoreKey {
    static let CoreDataNodeItem = "CoreDataNodeItem"
    static let LosslessConvertibleDictionary = "LosslessConvertibleDictionary"
}

/// A representation of a Type with internal property keys and values mapped to a NSDictionary that can be used in store
public protocol LosslessDictionaryConvertible {
    init?(dictionaryRepresentation: NSDictionary)
    func dictionaryRepresentation() -> NSDictionary
}

public protocol LosslessTextConvertible: LosslessDictionaryConvertible {
    init?(_ text: String)
}

public extension LosslessTextConvertible {
    
    init?(dictionaryRepresentation: NSDictionary) {
        guard let value = dictionaryRepresentation[CoreDataTallyStoreKey.LosslessConvertibleDictionary] as? Self else { return nil }
        self = value
    }
    
    func dictionaryRepresentation() -> NSDictionary {
        let dict = [CoreDataTallyStoreKey.LosslessConvertibleDictionary: self]
        return dict as NSDictionary
    }
}

fileprivate extension Node where Item: LosslessDictionaryConvertible {
    
    var itemType: CoreDataItemType {
        switch self {
        case .root: return CoreDataItemType.root
        case .item: return CoreDataItemType.item
        case .sequenceEnd: return CoreDataItemType.boundarySequenceEnd
        case .sequenceStart: return CoreDataItemType.boundarySequenceStart
        case .unseenLeadingItems: return CoreDataItemType.boundaryUnseenLeadingItems
        case .unseenTrailingItems: return CoreDataItemType.boundaryUnseenTrailingItems
        }
    }
    
    init?(itemDictionaryRepresentation: NSDictionary) {
        
        guard let dictionary = itemDictionaryRepresentation as? [String: AnyObject],
            let value = dictionary[CoreDataTallyStoreKey.CoreDataNodeItem],
            let itemDictionary = value as? NSDictionary,
            let item = Item(dictionaryRepresentation: itemDictionary)
            else { return nil }
        
            self = Node<Item>.item(item)
    }
    
    func itemDictionaryRepresentation() -> NSDictionary? {
        if let item = self.item {
            let dict = [CoreDataTallyStoreKey.CoreDataNodeItem: item.dictionaryRepresentation()]
            return dict as NSDictionary
        }
        else { return nil }
    }
}
