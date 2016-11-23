//
//  CoreDataTallyStore.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation
import CoreData

/// A representation of a Type with internal property keys and values mapped to a NSDictionary that can be used in store
public protocol LosslessConvertible {
    init?(_: CoreDataTallyStoreLosslessRepresentation)
    var losslessRepresentation: CoreDataTallyStoreLosslessRepresentation { get }
}

public enum CoreDataArchiveType {
    
    case binaryStore(at: URL)
    case sqliteStore(at: URL)
    
    var storeType: String {
        switch self {
        case .binaryStore: return NSBinaryStoreType
        case .sqliteStore: return NSSQLiteStoreType
        }
    }
    
    var url: URL {
        switch self {
        case .binaryStore(let url): return url
        case .sqliteStore(let url): return url
        }
    }
}

public class CoreDataTallyStore<Item>: TallyStoreType where Item: Hashable, Item: LosslessConvertible {
        
    private var stack: CoreDataStack
    private var root: CoreDataNodeWrapper<Item>
    private var backgroundRoot: CoreDataNodeWrapper<Item>
    
    static func stackIdentifier(named name: String) -> String {
        return "Tally.CoreDataStore." + name
    }
    
    public init(named name: String = "DefaultStore", fillFrom archive: CoreDataArchiveType? = nil, inMemory: Bool = false) {
        let identifier = CoreDataTallyStore.stackIdentifier(named: name)
        print("CoreDataTallyStore")
        print("- identifier:", identifier)
        print("- fillFrom:", archive as Any)
        print("- inMemory:", inMemory)
        
        self.stack = CoreDataStack(identifier: identifier, fromArchive: archive, inMemory: inMemory)
        self.root = stack.getRoot(from: stack.mainContext)
        
        stack.save(context: stack.mainContext)
        
        // ughhh
        let obj = stack.backgroundContext.object(with: root._node.objectID) as! CoreDataNode
        self.backgroundRoot = CoreDataNodeWrapper<Item>(node: obj, in: stack.backgroundContext)

        //self.backgroundRoot = stack.getRoot(from: stack.backgroundContext, and: rootId)
    }
    
    deinit {
        self.stack.save(context: stack.mainContext)
    }
    
    // TODO: After migrating to a sqlite archive, is it safe to only use the .sqlite file to restore?
    // If sqlite is chosen as the archive type, might need to manaully turn off wal option 
    // (which would need to be mirrored in the stack initilization)
    // see: https://developer.apple.com/library/content/qa/qa1809/_index.html
    // see: https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/CoreData/PersistentStoreFeatures.html
    // see: http://stackoverflow.com/questions/20969996/is-it-safe-to-delete-sqlites-wal-file
    public func archive(as archiveType: CoreDataArchiveType) throws {
        
        if let currentStore = self.stack.persistentContainer.persistentStoreCoordinator.persistentStores.last {
            try self.stack.persistentContainer.persistentStoreCoordinator.migratePersistentStore(currentStore, to: archiveType.url, options: nil, withType: archiveType.storeType)
        }
    }
    
    // MARK: TallyStoreType
    
    public func incrementCount(for sequence: [Node<Item>]) {
        incrementCount(for: sequence, completed: nil)
    }
    
    public func incrementCount(for sequence: [Node<Item>], completed closure: (() -> Void)? = nil) {
        
        if stack.inMemory {
            self.root.incrementCount(for: [Node<Item>.root] + sequence)
            closure?()
        }
        else {
            
            stack.mainContext.refreshAllObjects()
                    
            stack.backgroundContext.perform {
                self.backgroundRoot.incrementCount(for: [Node<Item>.root] + sequence)
                self.stack.save(context: self.stack.backgroundContext)
                closure?()
            }
        }
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.itemProbabilities(after: [Node<Item>.root] + sequence)
    }
    
    public func distributions(excluding excludedItems: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.distributions(excluding: excludedItems)
    }
}

// MARK: - CoreDataStack

fileprivate class CoreDataStack {
    
    let persistentContainer: NSPersistentContainer
    fileprivate let inMemory: Bool
    
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
    
    init(identifier storeName: String, fromArchive archive: CoreDataArchiveType? = nil, inMemory: Bool = false) {
        
        let bundle = Bundle(for: CoreDataStack.self) // check this works as expected in a module
        
        // TODO: Investigate option for creating model in code rather than as a resource
        // especially if this allows for the NSManagedObject subclasses to be automatically generated
        guard let modelUrl = bundle.url(forResource: "TallyStoreModel", withExtension: "momd"),
            let mom = NSManagedObjectModel(contentsOf: modelUrl)
            else { fatalError("Unresolved error") }
        
        self.persistentContainer = NSPersistentContainer(name: storeName, managedObjectModel: mom)
        self.inMemory = inMemory
        
        if let archive = archive {
            
            let storeUrl = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(storeName).appendingPathExtension("sqlite")
            
            if !FileManager.default.fileExists(atPath: storeUrl.path) {
                
                let archiveContainer = NSPersistentContainer(name: "ArchiveContainer", managedObjectModel: mom)
                
                let archiveDescription = NSPersistentStoreDescription(url: archive.url)
                archiveDescription.type = archive.storeType
                
                archiveContainer.persistentStoreDescriptions = [archiveDescription]
                archiveContainer.loadPersistentStores(completionHandler: { (storeDescription, error) in
                    
                    if let error = error { fatalError("Unresolved error \(error)") } // TODO: Manage error
                    
                    if let archiveStore = archiveContainer.persistentStoreCoordinator.persistentStores.last {
                        try! archiveContainer.persistentStoreCoordinator.migratePersistentStore(archiveStore, to: storeUrl, options: nil, withType: NSSQLiteStoreType)
                    }
                })
            }
            
            let description = NSPersistentStoreDescription(url: storeUrl)
            persistentContainer.persistentStoreDescriptions = [description]
        }
        
        if inMemory {
            print("Warning: Core Data using NSInMemoryStoreType, changes will not persist, use for testing only")
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            persistentContainer.persistentStoreDescriptions.append(description)
        }
        
        persistentContainer.loadPersistentStores{ (storeDescription, error) in
            print(storeDescription)
            if let error = error { fatalError("Unresolved error \(error)") } // TODO: Manage error
        }
    }
    
    private func fetchExistingRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item>? where Item: Hashable, Item: LosslessConvertible {
        
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
    
    fileprivate func getRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item> where Item: Hashable, Item: LosslessConvertible {
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

// TODO: Review if this is a bottleneck
// http://stackoverflow.com/a/32421787/1060154
fileprivate enum CoreDataItemType: Int {
    case root = 0
    case boundaryUnseenTrailingItems
    case boundaryUnseenLeadingItems
    case boundarySequenceStart
    case boundarySequenceEnd
    case literalItem
}

// MARK: - Node<Item> extension

fileprivate extension Node where Item: LosslessConvertible {
    
    var itemType: CoreDataItemType {
        switch self {
        case .item: return CoreDataItemType.literalItem
        case .root: return CoreDataItemType.root
        case .sequenceEnd: return CoreDataItemType.boundarySequenceEnd
        case .sequenceStart: return CoreDataItemType.boundarySequenceStart
        case .unseenLeadingItems: return CoreDataItemType.boundaryUnseenLeadingItems
        case .unseenTrailingItems: return CoreDataItemType.boundaryUnseenTrailingItems
        }
    }
}

// MARK: - TallyStoreNodeType

// can not extend NSManangedOjbect as a generic type, so using this as a wrapper
fileprivate struct CoreDataNodeWrapper<Item>: TallyStoreNodeType where Item: Hashable, Item: LosslessConvertible {
    
    fileprivate var _node: CoreDataNode
    private var context: NSManagedObjectContext
    
    init(node: CoreDataNode, in context: NSManagedObjectContext) {
        self._node = node
        self.context = context
    }
    
    init(in context: NSManagedObjectContext) {
        let root = CoreDataNode(node: Node<Item>.root, in: context)
        self.init(node: root, in: context)
    }
    
    init(item: Node<Item>, in context: NSManagedObjectContext) {
        let node = CoreDataNode(node: item, in: context)
        self.init(node: node, in: context)
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
    
    // profiling is showing that this is a bottleneck, especially the initializer
    internal var node: Node<Item> {
        
        switch self._node.itemType {
        case .root: return Node<Item>.root
        case .boundaryUnseenLeadingItems: return Node<Item>.unseenLeadingItems
        case .boundaryUnseenTrailingItems: return Node<Item>.unseenTrailingItems
        case .boundarySequenceStart: return Node<Item>.sequenceStart
        case .boundarySequenceEnd: return Node<Item>.sequenceEnd
            
        case .literalItem:
            // this is grabbing the transformable property
            guard let lossless = self._node.literalItem?.losslessRepresentation,
                let item = Item(lossless)
                else { fatalError("no internal representation \(self._node.literalItem?.losslessRepresentation)") }
            
            let node =  Node<Item>.item(item)
            return node
        }
    }
}

// MARK: - CoreDataNode Helper

fileprivate extension CoreDataNode {
    
    convenience init<Item: LosslessConvertible>(node: Node<Item>, in context: NSManagedObjectContext) {
        self.init(context: context)
        
        self.itemType = node.itemType
        
        if let losslessRepresentation = node.item?.losslessRepresentation {
            self.literalItem = CoreDataLiteralItem(with: losslessRepresentation, in: context)
        }
    }
    
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
}

fileprivate enum CoreDataLiteralItemType: Int {
    case string = 0
    case bool
    case int16
    case double
    case dictionary
}

public enum CoreDataTallyStoreLosslessRepresentation {
    
    case string(String)
    case bool(Bool)
    case int16(Int16)
    case double(Double)
    case dictionary(NSDictionary)
    
    init(_ item: CoreDataLiteralItem) {
        switch item.literalItemType {
        case .bool:
            self = .bool(item.boolRepresentation)
            
        case .string:
            self = .string(item.stringRepresentation!)
            
        case .double:
            self = .double(item.doubleRepresentation)
            
        case .dictionary:
            self = .dictionary(item.dictionaryRepresentation!)
            
        case .int16:
            self = .int16(item.int16Representation)
        }
    }
}

fileprivate extension CoreDataLiteralItem {
    
    convenience init(with losslessRepresentation: CoreDataTallyStoreLosslessRepresentation, in context: NSManagedObjectContext) {
        
        self.init(context: context)
        
        switch losslessRepresentation {
        case .bool(let representation):
            literalItemType = .bool
            boolRepresentation = representation
            
        case .string(let repersentation):
            literalItemType = .string
            stringRepresentation = repersentation
            
        case .double(let representation):
            literalItemType = .double
            doubleRepresentation = representation
            
        case .int16(let representation):
            literalItemType = .int16
            int16Representation = representation
            
        case .dictionary(let representation):
            literalItemType = .dictionary
            dictionaryRepresentation = representation
        }
    }
    
    var literalItemType: CoreDataLiteralItemType {
        set {
            self.literalItemTypeInt16Value = Int16(exactly: newValue.rawValue)!
        }
        get {
            guard let intFromInt16 = Int(exactly: self.literalItemTypeInt16Value),
                let type = CoreDataLiteralItemType(rawValue: intFromInt16) else {
                    fatalError("CoreDataLiteralItem internal representation inconsistancy")
            }
            return type
        }
    }
    
    var losslessRepresentation: CoreDataTallyStoreLosslessRepresentation {
        return CoreDataTallyStoreLosslessRepresentation(self)
    }
}

