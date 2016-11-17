//
//  CoreDataStoreTests.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import XCTest
@testable import Tally

class TallyTestsCoreDataStore: XCTestCase {
    
    func testStore() {
        
        // create a core data store, with an in-memory option (used for testing)
        let store = CoreDataTallyStore<String>(inMemory: true)
        
        // create a model using a CoreData store
        var model = Tally<String>()
        model.store = AnyTallyStore(store)
        model.observe(sequence: ["hello", "world"])
        model.observe(sequence: ["hello", "kitty"])
        
        // update model with observations
        let modelItemProbabilitiesAfterHello = model.itemProbabilities(after: "hello")
        XCTAssertTrue(modelItemProbabilitiesAfterHello.count == 2, "Unexpected number of probabilities")
        XCTAssertTrue(modelItemProbabilitiesAfterHello[0].probability == 0.5, "Unexpected probability")
        
        // create a new model, using the same store
        var newModel = Tally<String>()
        newModel.store = AnyTallyStore(store)
        
        // although this model hasn't observed any sequences, because it uses the same store, 
        // it should also have the same probabilities as the first model
        let newModelItemProbabilitiesAfterHello = newModel.itemProbabilities(after: "hello")
        XCTAssertTrue(newModelItemProbabilitiesAfterHello.count == 2, "Unexpected number of probabilities")
        XCTAssertTrue(newModelItemProbabilitiesAfterHello[0].probability == 0.5, "Unexpected probability")
    }
}

// Type needs to implement either LosslessTextConvertible, or LosslessDictionaryConvertible to be 
// used with a CoreDataTallyStore, for String it just needs an empty extension. 
extension String: LosslessTextConvertible {}
