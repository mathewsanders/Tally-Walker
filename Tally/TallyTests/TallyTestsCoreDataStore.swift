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
        
        let closureExpectation = expectation(description: "Closure")
        let closureGroup = DispatchGroup()
        
        // create a core data store, with an in-memory option (used for testing)
        let testSqlite = CoreDataStoreInformation(sqliteStoreNamed: "Test")
        try! testSqlite.destroyExistingPersistantStoreAndFiles()
        
        let store = try! CoreDataTallyStore<String>(store: testSqlite)
        
        // create a model using a CoreData store
        var model = Tally<String>()
        model.store = AnyTallyStore(store)
        
        closureGroup.enter()
        model.observe(sequence: ["hello", "world"]) {
            closureGroup.leave()
        }
        
        closureGroup.enter()
        model.observe(sequence: ["hello", "kitty"]) {
            closureGroup.leave()
        }
        
        closureGroup.notify(queue: DispatchQueue.main) {
            closureExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 1) { _ in
            // update model with observations
            let modelItemProbabilitiesAfterHello = model.itemProbabilities(after: "hello")
            dump(modelItemProbabilitiesAfterHello)
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
            
            try! testSqlite.destroyExistingPersistantStoreAndFiles()
        }
    }
    
    func testSimple() {
        
        let closureExpectation = expectation(description: "Closure")
        
        let testSqlite = CoreDataStoreInformation(sqliteStoreNamed: "Test")
        try! testSqlite.destroyExistingPersistantStoreAndFiles()
        
        // create a core data store, with an in-memory option (used for testing)
        let store = try! CoreDataTallyStore<String>(store: testSqlite)
        
        // create a model using a CoreData store
        var model = Tally<String>()
        model.store = AnyTallyStore(store)
        
        // update model with observations
        model.observe(sequence: ["hello", "world"]) {
            closureExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 1) { _ in
            let modelItemProbabilitiesAfterHello = model.itemProbabilities(after: "hello")
            dump(modelItemProbabilitiesAfterHello)
            
            try! testSqlite.destroyExistingPersistantStoreAndFiles()
        }
    }
    
    /// Create two core data models, distinguished by different names, that operate independently of each other
    func testNamedStores() {
        
        let closureExpectation = expectation(description: "Closure")
        let closureGroup = DispatchGroup()
        
        let birdsSqlite = CoreDataStoreInformation(sqliteStoreNamed: "Birds")
        try! birdsSqlite.destroyExistingPersistantStoreAndFiles()
        
        let birdStore = try! CoreDataTallyStore<String>(store: birdsSqlite)
        var birdModel = Tally<String>()
        birdModel.store = AnyTallyStore(birdStore)
        
        closureGroup.enter()
        birdModel.observe(sequence: ["tweet", "tweet"]) {
            closureGroup.leave()
        }
        
        let carsSqlite = CoreDataStoreInformation(sqliteStoreNamed: "Cars")
        try! carsSqlite.destroyExistingPersistantStoreAndFiles()
        
        let carStore = try! CoreDataTallyStore<String>(store: carsSqlite)
        var carModel = Tally<String>()
        carModel.store = AnyTallyStore(carStore)
        
        closureGroup.enter()
        carModel.observe(sequence: ["honk", "honk"]) {
            closureGroup.leave()
        }
        
        closureGroup.notify(queue: DispatchQueue.main) {
            closureExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 5) { _ in
            let birdModelItemProbabilitiesAfterTweet = birdModel.itemProbabilities(after: "tweet")
            let carModelItemProbabilitiesAfterHonk = carModel.itemProbabilities(after: "honk")
            
            // expect: [(0.5, "tweet"), (0.5, unseenTrailingItems)]
            dump(birdModelItemProbabilitiesAfterTweet)
            XCTAssertTrue(birdModelItemProbabilitiesAfterTweet.count == 2, "Unexpected number of probabilities")
            XCTAssertTrue(birdModelItemProbabilitiesAfterTweet[0].probability == 0.5, "Unexpected probability")
            
            dump(carModelItemProbabilitiesAfterHonk)
            // expect: [(0.5, "honk"), (0.5, unseenTrailingItems)]
            XCTAssertTrue(carModelItemProbabilitiesAfterHonk.count == 2, "Unexpected number of probabilities")
            XCTAssertTrue(carModelItemProbabilitiesAfterHonk[0].probability == 0.5, "Unexpected probability")
            
            try! birdsSqlite.destroyExistingPersistantStoreAndFiles()
            try! carsSqlite.destroyExistingPersistantStoreAndFiles()
        }
    }
}


extension String: LosslessConvertible {
    public var losslessRepresentation: CoreDataTallyStoreLosslessRepresentation {
        return .string(self)
    }
    
    public init?(_ representation: CoreDataTallyStoreLosslessRepresentation) {
        if case let .string(stringValue) = representation {
            self = stringValue
        }
        else { return nil }
    }
}
