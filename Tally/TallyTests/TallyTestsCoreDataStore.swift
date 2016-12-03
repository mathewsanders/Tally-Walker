// TallyTestsCoreDataStore.swift
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

import XCTest
import Tally

class TallyTestsCoreDataStore: XCTestCase {
    
    /// Create a two models, both backed by the same Core Data store
    func testStore() {
        
        let keepAlive = expectation(description: "keepAlive")
        
        // create a core data store, with an in-memory option (used for testing)
        let testSqlite = try! CoreDataStoreInformation(sqliteStoreNamed: "Test")
        try! testSqlite.destroyExistingPersistantStoreAndFiles()
        
        let store = try! CoreDataTallyStore<String>(store: testSqlite)
        
        // create a model using a CoreData store
        var model = Tally<String>()
        model.store = AnyTallyStore(store)
        
        model.observe(sequence: ["hello", "world"])
        model.observe(sequence: ["hello", "kitty"])
        
        store.save(completed: {
            keepAlive.fulfill()
        })
        
        waitForExpectations(timeout: 1) { _ in
            
            // update model with observations
            let dists = model.distributions()
            print("dists")
            dump(dists)
            
            let probabilitiesAfterHello = model.elementProbabilities(after: "hello")
            dump(probabilitiesAfterHello)
            XCTAssertTrue(probabilitiesAfterHello.count == 2, "Unexpected number of probabilities")
            XCTAssertTrue(probabilitiesAfterHello[0].probability == 0.5, "Unexpected probability")
            
            // create a new model, using the same store
            var newModel = Tally<String>()
            newModel.store = AnyTallyStore(store)
            
            // although this model hasn't observed any sequences, because it uses the same store,
            // it should also have the same probabilities as the first model
            let newModelProbabilitiesAfterHello = newModel.elementProbabilities(after: "hello")
            XCTAssertTrue(newModelProbabilitiesAfterHello.count == 2, "Unexpected number of probabilities")
            XCTAssertTrue(newModelProbabilitiesAfterHello[0].probability == 0.5, "Unexpected probability")
            
            try! testSqlite.destroyExistingPersistantStoreAndFiles()
        }
    }
    
    func testSimple() {
        
        let keepAlive = expectation(description: "keepAlive")
        
        let testStoreInformation = try! CoreDataStoreInformation(sqliteStoreNamed: "Test123")
        try! testStoreInformation.destroyExistingPersistantStoreAndFiles()

        let store = try! CoreDataTallyStore<String>(store: testStoreInformation)
        
        // create a model using a CoreData store
        var model = Tally<String>()
        model.store = AnyTallyStore(store)
        
        model.observe(sequence: ["hello", "again"])
        
        store.save(completed: {
            keepAlive.fulfill()
        })
        
        waitForExpectations(timeout: 1) { _ in
            let probabilitiesAfterHello = model.elementProbabilities(after: "hello")
            dump(probabilitiesAfterHello)
        }
    }
    
    /// Create two core data models, distinguished by different names, that operate independently of each other
    func testNamedStores() {
        
        let keepAlive = expectation(description: "keepAlive")
        
        let birdsSqlite = try! CoreDataStoreInformation(sqliteStoreNamed: "Birds")
        try! birdsSqlite.destroyExistingPersistantStoreAndFiles()
        
        let birdStore = try! CoreDataTallyStore<String>(store: birdsSqlite)
        var birdModel = Tally<String>()
        birdModel.store = AnyTallyStore(birdStore)
        
        birdModel.observe(sequence: ["tweet", "tweet"])
        
        let carsSqlite = try! CoreDataStoreInformation(sqliteStoreNamed: "Cars")
        try! carsSqlite.destroyExistingPersistantStoreAndFiles()
        
        let carStore = try! CoreDataTallyStore<String>(store: carsSqlite)
        var carModel = Tally<String>()
        carModel.store = AnyTallyStore(carStore)
        
        carModel.observe(sequence: ["honk", "honk"])
        
        let saves = DispatchGroup()
        
        saves.enter()
        birdStore.save(completed: {
            saves.leave()
        })
        
        saves.enter()
        carStore.save(completed: {
            saves.leave()
        })
        
        saves.notify(queue: .main, execute: {
            keepAlive.fulfill()
        })
        
        waitForExpectations(timeout: 5) { _ in
            
            let birdModelProbabilitiesAfterTweet = birdModel.elementProbabilities(after: "tweet")
            let carModelProbabilitiesAfterHonk = carModel.elementProbabilities(after: "honk")
            
            // expect: [(0.5, "tweet"), (0.5, unseenTrailingItems)]
            dump(birdModelProbabilitiesAfterTweet)
            XCTAssertTrue(birdModelProbabilitiesAfterTweet.count == 2, "Unexpected number of probabilities")
            XCTAssertTrue(birdModelProbabilitiesAfterTweet[0].probability == 0.5, "Unexpected probability")
            
            dump(carModelProbabilitiesAfterHonk)
            // expect: [(0.5, "honk"), (0.5, unseenTrailingItems)]
            XCTAssertTrue(carModelProbabilitiesAfterHonk.count == 2, "Unexpected number of probabilities")
            XCTAssertTrue(carModelProbabilitiesAfterHonk[0].probability == 0.5, "Unexpected probability")
            
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
