// CoreDataTallyStore.swift
//
// Copyright (c) 2016 Mathew Sanders
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CoreData

/// A type that can be converted to a type that can be stored as a Core Data entity property, and 
/// perfectly reconstructed from the stored type.
public protocol LosslessConvertible {
    init?(_: CoreDataTallyStoreLosslessRepresentation)
    var losslessRepresentation: CoreDataTallyStoreLosslessRepresentation { get }
}

/**
 Error raised when using CoreDataTallyStore
 
 - missingModelObjectModel: The file 'TallyStoreModel.xcdatamodeld' could not be loaded.
 - coreDataNodeLoadToContextFailed: Attempt to load a node into a new context has failed.
 - save: Attempt to save context has failed.
 - noStoreToArchive: Request to archive a store failed because store does not exist.
 
 */
enum CoreDataTallyStoreError: Error {
    case missingModelObjectModel
    case coreDataNodeLoadToContextFailed
    case otherError(NSError)
    case noStoreToArchive
    case storeNotLoaded
}

// MARK: - CoreDataTallyStore

public class CoreDataTallyStore<Item>: TallyStoreType where Item: Hashable, Item: LosslessConvertible {
        
    private let stack: CoreDataStack
    private var mainRoot: CoreDataNodeWrapper<Item>
    private var backgroundRoot: CoreDataNodeWrapper<Item>
    
    public init(store storeInformation: CoreDataStoreInformation, fillFrom archive: CoreDataStoreInformation? = nil) throws {
        self.stack = try CoreDataStack(store: storeInformation, fromArchive: archive)
        self.mainRoot = stack.getRoot(from: stack.mainContext)
        self.backgroundRoot = try mainRoot.loaded(in: stack.backgroundContext)
    }
    
    public convenience init(named name: String = "DefaultStore", fillFrom archive: CoreDataStoreInformation? = nil) throws {
        let storeInformation = try CoreDataStoreInformation(sqliteStoreNamed: name, in: .defaultDirectory)
        try self.init(store: storeInformation, fillFrom: archive)
    }
    
    deinit {
        save()
    }
    
    /**  
     Save is performed on the same background context queue as observation occurs, so save will not occur
     untill observations have been completed.
     
     - parameter completed: A closure object containing behaviour to perform once save is completed. This closure is performed on the main thread.
    */
    public func save(completed: (() -> Void)? = nil) {
        // Main context is configured to be generational and to automatically consume save notifications 
        // from other (e.g. background) contexts.
        try! self.stack.save(context: self.stack.backgroundContext, completed: {
            DispatchQueue.main.async {
                completed?()
            }
        })
    }
    
    public func archive(as archiveStore: CoreDataStoreInformation) throws {
        try stack.archive(as: archiveStore)
    }
    
    // MARK: TallyStoreType
    public func incrementCount(for sequence: [Node<Item>]) {
        incrementCount(for: sequence, completed: nil)
    }
    
    public func incrementCount(for sequence: [Node<Item>], completed closure: (() -> Void)? = nil) {
        stack.backgroundContext.perform {
            self.backgroundRoot.incrementCount(for: [Node<Item>.root] + sequence)
            closure?() // TODO: Consider calling on main queue
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
    let storeInformation: CoreDataStoreInformation
    
    init(store storeInformation: CoreDataStoreInformation, fromArchive archive: CoreDataStoreInformation? = nil) throws {

        // load the mom
        guard let momUrl = Bundle(for: CoreDataStack.self).url(forResource: "TallyStoreModel", withExtension: "momd"),
            let mom = NSManagedObjectModel(contentsOf: momUrl)
            else { throw CoreDataTallyStoreError.missingModelObjectModel }
        
        var storeLoadError: Error?
        
        // request to load store with contents of an achived store
        if let archive = archive {
            
            // if the store already exists, then don't import from the archive
            if !FileManager.default.fileExists(atPath: storeInformation.url.path) {
                
                // initalize archive container and load
                let archiveContainer = NSPersistentContainer(name: "ArchiveContainer", managedObjectModel: mom)
                archiveContainer.persistentStoreDescriptions = [archive.description]
                archiveContainer.loadPersistentStores { _, error in storeLoadError = error }
                
                // migrate the archive to the sqlite location
                guard let archivedStore = archiveContainer.persistentStoreCoordinator.persistentStore(for: archive.url), storeLoadError == nil
                    else { throw storeLoadError! }
                
                // Stores archived by CoreDataStack apply manual vacuum and set journal mode to DELETE
                // Need to test to see if nil options are passed through the archive options are used
                // of if the persistant store coordiantors default options are used instead
                /*
                let options: [String: Any] = [
                    NSSQLiteManualVacuumOption: false,
                    NSSQLitePragmasOption: ["journal_mode": "WAL"]
                ]
                */
                
                try archiveContainer.persistentStoreCoordinator.migratePersistentStore(archivedStore, to: storeInformation.url, options: nil, withType: storeInformation.type)
            }
        }
        
        // initalize store container and load
        storeContainer = NSPersistentContainer(name: "StoreContainer", managedObjectModel: mom)
        storeContainer.persistentStoreDescriptions = [storeInformation.description]
        storeContainer.loadPersistentStores { description, error in
            storeLoadError = error
            print("Store loaded:", description)
        }
        
        guard let _ = storeContainer.persistentStoreCoordinator.persistentStore(for: storeInformation.url), storeLoadError == nil
            else {
                print(storeLoadError)
                throw CoreDataTallyStoreError.storeNotLoaded
            }
        
        // assign main context and background context
        // merge policy needs to be set because of unique constraint on literal item managed objects
        // `automaticallyMergesChangesFromParent` is set on the main context so that when saves are 
        // made on the background context, the main context automatically attempts to refresh any objects
        // that are currently in context.
        self.mainContext = storeContainer.viewContext
        mainContext.automaticallyMergesChangesFromParent = true
        mainContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        self.backgroundContext =  storeContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        self.storeInformation = storeInformation
        
    }
    
    private func fetchExistingRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item>? where Item: Hashable, Item: LosslessConvertible {
        // TODO: - could also store the root object id as metadata in the store?
        // see: https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/CoreData/PersistentStoreFeatures.html
        
        // look for root by fetching node with no parent
        let request: NSFetchRequest<CoreDataNode> = CoreDataNode.fetchRequest()
        request.fetchLimit = 2 // there should only be a single root, but set limit to 2 so we can do a sanity check
        request.predicate = NSPredicate(format: "parent = nil")
        request.relationshipKeyPathsForPrefetching = ["children"] // TODO: Profile to see if this still have an impact
        
        do {
            let rootItems = try context.fetch(request)
            guard let rootItem = rootItems.first, rootItems.count == 1
                else { return nil }
            
            return CoreDataNodeWrapper<Item>(node: rootItem, in: context)
        }
        catch { return nil }
    }
    
    fileprivate func getRoot<Item>(from context: NSManagedObjectContext) -> CoreDataNodeWrapper<Item> where Item: Hashable, Item: LosslessConvertible {
        return fetchExistingRoot(from: context) ?? CoreDataNodeWrapper<Item>(in: context)
    }
    
    fileprivate func save(context: NSManagedObjectContext, completed: (() -> Void)? = nil) throws {
        
        var saveError: NSError?
        
        // always perform save in correct thread
        context.perform {
            
            // if there are no changes, then return early
            guard context.hasChanges else {
                completed?()
                return
            }
            
            // attempt a save, if save fails log and save the error to throw later
            do {
                try context.save()
            }
            catch {
                print("save error...")
                print(error.localizedDescription)
                saveError = error as NSError
            }
            completed?()
            
        }
        
        // if an error was caught, throw it up to the method caller
        if let error = saveError {
            throw CoreDataTallyStoreError.otherError(error)
        }
    }
    
    // see: https://developer.apple.com/library/content/qa/qa1809/_index.html
    // see: https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/CoreData/PersistentStoreFeatures.html
    // see: http://stackoverflow.com/questions/20969996/is-it-safe-to-delete-sqlites-wal-file
    fileprivate func archive(as archiveStore: CoreDataStoreInformation) throws {
        
        guard let currentStore = self.storeContainer.persistentStoreCoordinator.persistentStore(for: storeInformation.url)
            else { throw CoreDataTallyStoreError.noStoreToArchive }
        
        let options: [String: Any]? = {
            switch archiveStore {
            case .sqliteStore:
                return [NSSQLitePragmasOption: ["journal_mode": "DELETE"], NSSQLiteManualVacuumOption: true]
            default:
                return nil
            }
        }()
        
        try self.storeContainer.persistentStoreCoordinator.migratePersistentStore(currentStore, to: archiveStore.url, options: options, withType: archiveStore.type)
    }
}

// MARK: - CoreDataNodeWrapper

// can not extend NSManangedOjbect as a generic type, so using this as a wrapper

fileprivate final class CoreDataNodeWrapper<Item>: TallyStoreNodeType where Item: Hashable, Item: LosslessConvertible {
    
    fileprivate var _node: CoreDataNode
    private var context: NSManagedObjectContext
    
    private var childSet: Set<CoreDataNode> {
        return self._node.children as? Set<CoreDataNode> ?? Set<CoreDataNode>()
    }
    
    init(node: CoreDataNode, in context: NSManagedObjectContext) {
        self._node = node
        self.context = context
    }
    
    convenience init(in context: NSManagedObjectContext) {
        let root = CoreDataNode(node: Node<Item>.root, in: context)
        self.init(node: root, in: context)
    }
    
    convenience init(item: Node<Item>, in context: NSManagedObjectContext) {
        let node = CoreDataNode(node: item, in: context)
        self.init(node: node, in: context)
    }
    
    func loaded(in context: NSManagedObjectContext) throws -> CoreDataNodeWrapper {
        guard let node: CoreDataNode = _node.loaded(in: context)
            else { throw CoreDataTallyStoreError.coreDataNodeLoadToContextFailed }
        
        return CoreDataNodeWrapper<Item>(node: node, in: context)
    }
    
    var count: Double {
        get { return _node.count }
        set { _node.count = newValue }
    }
    
    var childNodes: AnySequence<CoreDataNodeWrapper<Item>> {
        return AnySequence(childSet.lazy.map{ return CoreDataNodeWrapper(node: $0, in: self.context) })
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

extension Dictionary {
    init(elements:[(Key, Value)]) {
        self.init()
        for (key, value) in elements {
            updateValue(value, forKey: key)
        }
    }
}
