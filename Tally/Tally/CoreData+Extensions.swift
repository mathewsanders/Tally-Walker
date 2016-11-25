//
//  CoreData+Extensions.swift
//  Tally
//
//  Created by Mathew Sanders on 11/25/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import CoreData

public enum CoreDataStoreInformation {
    
    case binaryStore(at: URL)
    case sqliteStore(at: URL)
    
    public init(sqliteStoreNamed name: String) {
        let url = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(name).appendingPathExtension("sqlite")
        self = .sqliteStore(at: url)
    }
    
    public init(binaryStoreNamed name: String) {
        let url = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(name).appendingPathExtension("binary")
        self = .binaryStore(at: url)
    }
    
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
        let _description = NSPersistentStoreDescription(url: url)
        _description.type = type
        return _description
    }
    
    public func destroyExistingPersistantStoreAndFiles() throws {
        
        // sqlite stores are truncated, not deleted
        let storeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try storeCoordinator.destroyPersistentStore(at: url, ofType: type, options: nil)
        
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
}

fileprivate extension URL {
    func appendingToPathExtension(_ string: String) -> URL {
        let pathExtension = self.pathExtension + string
        return self.deletingPathExtension().appendingPathExtension(pathExtension)
    }
}

extension NSManagedObject {
    
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
            context.performAndWait {
                do {
                    object = try context.existingObject(with: self.objectID) as? ManagedObjectType
                }
                    // catch error from loading object from id
                catch let error { print(error) }
            }
        }
            // catch error from saving original context
        catch let error { print(error) }
        
        // if everything has gone without error, this will be the `this` object
        // loaded in the new context, otherwise it will be `nil`
        return object
    }
}
