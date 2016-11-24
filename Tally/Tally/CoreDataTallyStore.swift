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

enum CoreDataTallyStoreError: Error {
    case missingModelObjectModel
    case noStoreToArchive
    case save(NSError)
}

public enum CoreDataStoreInformation {
    
    case binaryStore(at: URL)
    case sqliteStore(at: URL)
    
    var type: String {
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
    
    var description: NSPersistentStoreDescription {
        let archiveDescription = NSPersistentStoreDescription(url: url)
        archiveDescription.type = type
        return archiveDescription
    }
}

// MARK: - CoreDataTallyStore

public class CoreDataTallyStore<Item>: TallyStoreType where Item: Hashable, Item: LosslessConvertible {
        
    private var stack: CoreDataStack
    private var mainRoot: CoreDataNodeWrapper<Item>
    private var backgroundRoot: CoreDataNodeWrapper<Item>
    
    public init(named name: String = "DefaultStore", fillFrom archive: CoreDataStoreInformation? = nil) throws {
        
        self.stack = try CoreDataStack(storeName: name, fromArchive: archive)
        
        let root: CoreDataNodeWrapper<Item> = stack.getRoot(from: stack.mainContext)
        let rootNode = stack.backgroundContext.object(with: root._node.objectID) as? CoreDataNode ?? root._node
        try self.stack.save(context: stack.mainContext)
        
        self.mainRoot = root
        self.backgroundRoot = CoreDataNodeWrapper<Item>(node: rootNode, in: stack.backgroundContext)
    }
    
    public func save() {
        try! self.stack.save(context: stack.mainContext)
    }
    
    deinit {
        save()
    }
    
    // TODO: After migrating to a sqlite archive, is it safe to only use the .sqlite file to restore?
    // If sqlite is chosen as the archive type, might need to manaully turn off wal option 
    // (which would need to be mirrored in the stack initilization)
    // see: https://developer.apple.com/library/content/qa/qa1809/_index.html
    // see: https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/CoreData/PersistentStoreFeatures.html
    // see: http://stackoverflow.com/questions/20969996/is-it-safe-to-delete-sqlites-wal-file
    public func archive(as archiveType: CoreDataStoreInformation) throws {
        guard let currentStore = self.stack.storeContainer.persistentStoreCoordinator.persistentStores.first
            else { throw CoreDataTallyStoreError.noStoreToArchive }
        
        try self.stack.storeContainer.persistentStoreCoordinator.migratePersistentStore(currentStore, to: archiveType.url, options: nil, withType: archiveType.type)
    }
    
    // MARK: TallyStoreType
    public func incrementCount(for sequence: [Node<Item>]) {
        incrementCount(for: sequence, completed: nil)
    }
    
    public func incrementCount(for sequence: [Node<Item>], completed closure: (() -> Void)? = nil) {
        stack.mainContext.refreshAllObjects() // TODO: Understand what this does, and if it's needed
        
        stack.backgroundContext.perform {
            self.backgroundRoot.incrementCount(for: [Node<Item>.root] + sequence)
            try! self.stack.save(context: self.stack.backgroundContext)
            closure?()
        }
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return mainRoot.itemProbabilities(after: [Node<Item>.root] + sequence)
    }
    
    public func distributions(excluding excludedItems: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return mainRoot.distributions(excluding: excludedItems)
    }
}

// MARK: - CoreDataStack

fileprivate class CoreDataStack {
    
    let storeContainer: NSPersistentContainer
    let mainContext: NSManagedObjectContext
    let backgroundContext: NSManagedObjectContext
    
    init(storeName: String, fromArchive archive: CoreDataStoreInformation? = nil) throws {
        
        // location for the sqlite store
        let storeUrl = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(storeName).appendingPathExtension("sqlite")
        let store: CoreDataStoreInformation = .sqliteStore(at: storeUrl)
        
        // load the mom
        guard let momUrl = Bundle(for: CoreDataStack.self).url(forResource: "TallyStoreModel", withExtension: "momd"),
            let mom = NSManagedObjectModel(contentsOf: momUrl)
            else { throw CoreDataTallyStoreError.missingModelObjectModel }
        
        var storeLoadError: Error?
        
        // request to load store with contents of an achived store
        if let archive = archive {
            
            // if the store already exists, then don't import from the archive
            if !FileManager.default.fileExists(atPath: store.url.path) {
                
                // initalize archive container and load
                let archiveContainer = NSPersistentContainer(name: "ArchiveContainer", managedObjectModel: mom)
                archiveContainer.persistentStoreDescriptions = [archive.description]
                archiveContainer.loadPersistentStores { _, error in storeLoadError = error }
                
                // migrate the archive to the sqlite location
                guard let archivedStore = archiveContainer.persistentStoreCoordinator.persistentStores.first, storeLoadError == nil
                    else { throw storeLoadError! }
                
                try archiveContainer.persistentStoreCoordinator.migratePersistentStore(archivedStore, to: store.url, options: nil, withType: store.type)
            }
        }
        
        // initalize store container and load
        storeContainer = NSPersistentContainer(name: storeName, managedObjectModel: mom)
        storeContainer.persistentStoreDescriptions = [store.description]
        storeContainer.loadPersistentStores { _, error in storeLoadError = error }
        
        guard let _ = storeContainer.persistentStoreCoordinator.persistentStores.first, storeLoadError == nil
            else { throw storeLoadError! }
        
        // initalize contexts
        mainContext = CoreDataStack.configure(context: storeContainer.viewContext)
        backgroundContext = CoreDataStack.configure(context: storeContainer.newBackgroundContext())
    }
    
    private func fetchExistingRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item>? where Item: Hashable, Item: LosslessConvertible {
        
        // look for root by fetching node with no parent
        let request: NSFetchRequest<CoreDataNode> = CoreDataNode.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "parent = nil")
        request.relationshipKeyPathsForPrefetching = ["children"]
        
        do {
            let rootItems = try context.fetch(request)
            guard let rootItem = rootItems.first
                else { return nil }
            
            return CoreDataNodeWrapper<Item>(node: rootItem, in: context)
        }
        catch { return nil }
    }
    
    fileprivate func getRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item> where Item: Hashable, Item: LosslessConvertible {
        return fetchExistingRoot(from: context) ?? CoreDataNodeWrapper<Item>(in: context)
    }
    
    fileprivate func save(context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    static func configure(context: NSManagedObjectContext) -> NSManagedObjectContext {
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }
}

// MARK: - CoreDataNodeWrapper

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
    
    var count: Double {
        get { return _node.count }
        set { _node.count = newValue }
    }
    
    var childNodes: AnySequence<CoreDataNodeWrapper<Item>> {
        guard let childrenSet = _node.children as? Set<CoreDataNode> else {
            let empty: [CoreDataNodeWrapper<Item>] = []
            return AnySequence(empty)
        }
        return AnySequence(childrenSet.lazy.map{ return CoreDataNodeWrapper(node: $0, in: self.context) })
    }
    
    func findChildNode(with item: Node<Item>) -> CoreDataNodeWrapper<Item>? {
        return childNodes.first(where: { childNode in
            return childNode.item(is: item)
        })
    }
    
    // nodeType is cheaper check than unrwapping node, so do this first
    private func item(is node: Node<Item>) -> Bool {
        return self._node.itemType == node.itemType && node == self.node
    }
    
    func makeChildNode(with item: Node<Item>) -> CoreDataNodeWrapper<Item> {
        let child = CoreDataNodeWrapper(item: item, in: context)
        child._node.parent = _node
        return child
    }
    
    // profiling is showing that this is a bottleneck, especially the initializer
    var node: Node<Item> {
        
        switch self._node.itemType {
        case .root: return Node<Item>.root
        case .boundaryUnseenLeadingItems: return Node<Item>.unseenLeadingItems
        case .boundaryUnseenTrailingItems: return Node<Item>.unseenTrailingItems
        case .boundarySequenceStart: return Node<Item>.sequenceStart
        case .boundarySequenceEnd: return Node<Item>.sequenceEnd
            
        case .literalItem:
            // grab the lossless representation of the literal item, this could involve expensive transformable property
            let losslessRepresentation = self._node.literalItem?.losslessRepresentation
            guard let lossless = losslessRepresentation, let item = Item(lossless)
                else { fatalError("CoreDataNodeWrapper internal inconsistancy \(losslessRepresentation)") }
            
            return Node<Item>.item(item)
        }
    }
}

// MARK: - NSManagedObject (CoreDataNode)

// TODO: Review if this is a bottleneck
// http://stackoverflow.com/a/32421787/1060154
fileprivate enum CoreDataItemType: Int16 {
    case root = 0
    case boundaryUnseenTrailingItems
    case boundaryUnseenLeadingItems
    case boundarySequenceStart
    case boundarySequenceEnd
    case literalItem
}

fileprivate extension CoreDataNode {
    
    convenience init<Item: LosslessConvertible>(node: Node<Item>, in context: NSManagedObjectContext) {
        self.init(context: context)
        
        self.itemType = node.itemType
        
        if let losslessRepresentation = node.item?.losslessRepresentation {
            self.literalItem = CoreDataLiteralItem(with: losslessRepresentation, in: context)
        }
    }
    
    var itemType: CoreDataItemType {
        set { itemTypeInt16Value = newValue.rawValue }
        get {
            guard let type = CoreDataItemType(rawValue: itemTypeInt16Value)
                else { fatalError("CoreDataNode internal inconsistancy \(itemTypeInt16Value)") }
            
            return type
        }
    }
}

// MARK: - NSManagedObject (CoreDataLiteralItem)

fileprivate enum CoreDataLiteralItemType: Int16 {
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
        case .bool: self = .bool(item.boolRepresentation)
        case .string: self = .string(item.stringRepresentation!)
        case .double: self = .double(item.doubleRepresentation)
        case .int16: self = .int16(item.int16Representation)
        case .dictionary: self = .dictionary(item.dictionaryRepresentation!)
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
        set { literalItemTypeInt16Value = newValue.rawValue }
        get {
            guard let type = CoreDataLiteralItemType(rawValue: literalItemTypeInt16Value)
                else { fatalError("CoreDataLiteralItem internal inconsistancy \(literalItemTypeInt16Value)") }
            
            return type
        }
    }
    
    var losslessRepresentation: CoreDataTallyStoreLosslessRepresentation {
        return CoreDataTallyStoreLosslessRepresentation(self)
    }
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
