//
//  CoreDataStoreTests.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import XCTest
import Tally

class TallyTestsCoreDataStore: XCTestCase {
    
    /// Create a two models, both backed by the same Core Data store
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
    
    /// Create two core data models, distinguished by different names, that operate independently of each other
    func testNamedStores() {
        
        let birdStore = CoreDataTallyStore<String>(named: "Birds", inMemory: true)
        var birdModel = Tally<String>()
        birdModel.store = AnyTallyStore(birdStore)
        birdModel.observe(sequence: ["tweet", "tweet"])
        
        let carStore = CoreDataTallyStore<String>(named: "Cars", inMemory: true)
        var carModel = Tally<String>()
        carModel.store = AnyTallyStore(carStore)
        carModel.observe(sequence: ["honk", "honk"])
        
        let birdModelItemProbabilitiesAfterTweet = birdModel.itemProbabilities(after: "tweet")
        let carModelItemProbabilitiesAfterHonk = carModel.itemProbabilities(after: "honk")
        
        // expect: [(0.5, "tweet"), (0.5, unseenTrailingItems)]
        XCTAssertTrue(birdModelItemProbabilitiesAfterTweet.count == 2, "Unexpected number of probabilities")
        XCTAssertTrue(birdModelItemProbabilitiesAfterTweet[0].probability == 0.5, "Unexpected probability")
        
        // expect: [(0.5, "honk"), (0.5, unseenTrailingItems)]
        XCTAssertTrue(carModelItemProbabilitiesAfterHonk.count == 2, "Unexpected number of probabilities")
        XCTAssertTrue(carModelItemProbabilitiesAfterHonk[0].probability == 0.5, "Unexpected probability")
        
    }
    
    // TODO: Update ABC.sqlite example with new schema
    func testLoadFromExistingStore() {
        
        guard let storeUrl = Bundle(for: TallyTestsCoreDataStore.self).url(forResource: "ABC", withExtension: "sqlite") else {
            XCTFail("sqlite file does not exist")
            return
        }
        
        let store = CoreDataTallyStore<String>(named: "ABC", restoreFrom: storeUrl)
        var model = Tally<String>()
        model.store = AnyTallyStore(store)
        
        // model is previously build by observing sequence ["a", "b", "c", "d"]
        
        let probabilities = model.itemProbabilities(after: "a")
        XCTAssertTrue(probabilities.count == 1, "Unexpected number of probabilities")
        XCTAssertTrue(probabilities[0] == (probability: 1.0, item: Node.item("b")), "Unexpected probability")
        
    }
}

// Type needs to implement either LosslessTextConvertible, or LosslessDictionaryConvertible to be 
// used with a CoreDataTallyStore, for String it just needs an empty extension. 
extension String: LosslessTextConvertible {}
