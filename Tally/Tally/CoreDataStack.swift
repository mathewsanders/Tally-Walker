//
//  CoreDataStack.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation
import CoreData

class CoreDataStack {
    
    lazy var persistentContainer: NSPersistentContainer = {
        
        guard let bundle = Bundle(identifier: "com.mathewsanders.Tally"),
            let modelUrl = bundle.url(forResource: "TallyStoreModel", withExtension: "momd"),
            let mom = NSManagedObjectModel(contentsOf: modelUrl)
        else {
            fatalError("Unresolved error")
        }
        
        let container = NSPersistentContainer(name: "TallyStoreModel", managedObjectModel: mom)
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                fatalError("Unresolved error \(error)")
            }
        })
        print("CoreDataStack returning persistentContainer")
        return container
    }()
    
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch let error as NSError {
                fatalError("Unresolved error \(error.description)")
            }      
        }
    } 
}
