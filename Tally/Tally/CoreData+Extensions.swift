// CoreData+Extensions.swift
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

/// Information used with creating a Core Data persistant store.
public enum CoreDataStoreInformation {
    
    case sqliteStore(at: URL)
    case binaryStore(at: URL)
    case inMemoryStore(at: URL)
    
    /**
    Physical location of the persistant store
     
    - mainBundle: the application's main bundle, resources here are read only.
    - defaultDirectory: the default directory created by NSPersistentContainer, resources here are read/write safe.
    - directory(at: URL): any other location, caller is responsable for read/write safety of the resource.
     */
    public enum Location {
        case mainBundle
        case defaultDirectory
        case directory(at: URL)
    }
    
    /**
    Error raised when using CoreDataStoreInformation
     
    - mainBundleResourceNotFound:
        Attempted to initilize `CoreDataStoreInformation` describing a resource within the main bundle that does not exist
     
     */
    enum CoreDataStoreInformationError: Error {
        case mainBundleResourceNotFound
    }
    
    /**
    Initializes information for a sqlite resource with a name, extension, and location.
     
    - Parameters:
        - resourceName: The name of the resource.
        - resourceExtension: The extension of the resource, default is 'sqlite'.
        - location: Location of the resource, default is `Location.defaultDirectory`.
     
     - Throws: CoreDataStoreInformationError.mainBundleResourceNotFound when attempting to describe a resource in the main bundle that does not exist.
     */
    public init(sqliteStoreNamed resourceName: String, with resourceExtension: String = "sqlite", in location: Location = .defaultDirectory) throws {
        let url = try CoreDataStoreInformation.url(for: resourceName, extension: resourceExtension, location: location)
        self = .sqliteStore(at: url)
    }
    
    /**
     Initializes information for a binary resource with a name, extension, and location.
     
     - Parameters:
        - resourceName: The name of the resource.
        - resourceExtension: The extension of the resource, default is 'binary'.
        - location: Location of the resource, default is `Location.defaultDirectory`.
     
     - Throws: CoreDataStoreInformationError.mainBundleResourceNotFound when attempting to describe a resource in the main bundle that does not exist.
     */
    public init(binaryStoreNamed resourceName: String, with resourceExtension: String = "binary", in location: Location = .defaultDirectory) throws {
        let url = try CoreDataStoreInformation.url(for: resourceName, extension: resourceExtension, location: location)
        self = .binaryStore(at: url)
    }
    
    public init(memoryStoreNamed resourceName: String, with resourceExtension: String = "memory", in location: Location = .defaultDirectory) throws {
        let url = try CoreDataStoreInformation.url(for: resourceName, extension: resourceExtension, location: location)
        self =  .inMemoryStore(at: url)
    }
    
    var type: String {
        switch self {
        case .binaryStore: return NSBinaryStoreType
        case .sqliteStore: return NSSQLiteStoreType
        case .inMemoryStore: return NSInMemoryStoreType
        }
    }
    
    var url: URL {
        switch self {
        case .binaryStore(let url): return url
        case .sqliteStore(let url): return url
        case .inMemoryStore(at: let url): return url
        }
    }
    
    var description: NSPersistentStoreDescription {
        let _description = NSPersistentStoreDescription(url: url)
        _description.type = type
        return _description
    }
    
    /**
     Attempts to safely tear down a persistant store, and remove physical components.
     
     Throws: 
        - Will (presumably) throw an error if the if the store can not be safely removed.
        - Will throw an error if attempting to remove a resource from the mainBundle.
     */
    public func destroyExistingPersistantStoreAndFiles() throws {
        
        // items in the application bundle are read only
        
        // sqlite stores are truncated, not deleted
        let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try storeCoordinator.destroyPersistentStore(at: url, ofType: type, options: nil)
        
        // in-memory stores have no file, and binary are deleted by `destroyPersistentStore`.
        if case .sqliteStore = self {
            // attempt to delete sqlite file and assocaited -wal and -shm files
            try deleteFileIfExists(fileUrl: url)
            try deleteFileIfExists(fileUrl: url.appendingToPathExtension("-wal"))
            try deleteFileIfExists(fileUrl: url.appendingToPathExtension("-shm"))
        }
    }
    
    private func deleteFileIfExists(fileUrl: URL) throws {
        if FileManager.default.fileExists(atPath: fileUrl.path) && FileManager.default.isDeletableFile(atPath: fileUrl.path) {
            try FileManager.default.removeItem(at: fileUrl)
        }
    }
    
    private static func url(for resourceName: String, extension resourceExtension: String, location: Location) throws -> URL {
        
        switch location {
        case .directory(at: let baseURL):
            return baseURL.appendingPathComponent(resourceName).appendingPathExtension(resourceExtension)
            
        case .defaultDirectory:
            return NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(resourceName).appendingPathExtension(resourceExtension)
            
        case .mainBundle:
            guard let bundleUrl = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
                else { throw CoreDataStoreInformationError.mainBundleResourceNotFound }
            
            return bundleUrl
        }
    }
}

fileprivate extension URL {
    func appendingToPathExtension(_ string: String) -> URL {
        let pathExtension = self.pathExtension + string
        return self.deletingPathExtension().appendingPathExtension(pathExtension)
    }
}

extension NSManagedObject {
    
    /**
     Attempts to safely load this object in a new context.
     
     **Note:** This method may perform I/O to the backing persistant store.
     
     Will fail in the following situations: 
     - This object does not have a managed object context.
     - This object has changes, but could not be saved.
     - The backing persistant store does not have a record of this object.
     
     Returns: `nil` if this object could not be loaded into the new context, otherwise returns an instance of NSManagedObject in the new context.
     
     */
    func loaded<ManagedObjectType: NSManagedObject>(in context: NSManagedObjectContext) -> ManagedObjectType? {
        
        var object: ManagedObjectType? = nil
        
        guard let originalContext = managedObjectContext
            else { return object }
        
        do {
            // save to ensure that object id is perminant, and so this node is persisted to store
            // and can be obtained by a cousin context
            if originalContext.hasChanges {
                try originalContext.save()
            }
            
            // use object id to load into the new context
            // see also: https://medium.com/bpxl-craft/some-lessons-learned-on-core-data-5f095ecb1882#.mzee3j5vf
            // TODO: Create an asynchronous version.
            context.performAndWait {
                do {
                    object = try context.existingObject(with: self.objectID) as? ManagedObjectType
                }
                    // catch error from loading object from id
                catch { print(error) }
            }
        }
            // catch error from saving original context
        catch { print(error) }
        
        // if everything has gone without error, this will be the `this` object
        // loaded in the new context, otherwise it will be `nil`
        return object
    }
}


// MARK: - CoreDataStack

internal class CoreDataStack {
    
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
    
    func save(context: NSManagedObjectContext, completed: (() -> Void)? = nil) throws {
        
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
    func archive(as archiveStore: CoreDataStoreInformation) throws {
        
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
