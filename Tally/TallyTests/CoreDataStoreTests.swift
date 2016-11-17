//
//  CoreDataStoreTests.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import XCTest
@testable import Tally

class CoreDataStoreTests: XCTestCase {
    
    func testStore() {
        
        let store = CoreDataTallyStore<String>()
        
        var originalModel = Tally<String>()
        originalModel.store = AnyTallyStore(store)
        originalModel.observe(sequence: ["hello", "world"])
        originalModel.observe(sequence: ["hello", "kitty"])

        var newModel = Tally<String>()
        newModel.store = AnyTallyStore(store)
        
        print("\n** original model **")
        dump(originalModel.itemProbabilities(after: "hello"))
        
        print("\n** new model **")
        dump(newModel.itemProbabilities(after: "hello"))
        
        //store.stack.saveContext()
    }
}

extension String: LosslessTextConvertible {}
