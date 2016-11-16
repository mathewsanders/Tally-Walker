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
        originalModel.delegate = AnyTallyStore(store)
        originalModel.observe(sequence: ["hello", "world"])
        originalModel.observe(sequence: ["hello", "kitty"])

        var newModel = Tally<String>()
        newModel.delegate = AnyTallyStore(store)
        
        print("\n** store **")
        dump(store)
        
        print("\n** original model **")
        dump(originalModel.itemProbabilities(after: "hello"))
        
        print("\n** new model **")
        dump(newModel.itemProbabilities(after: "hello"))
        
        print("\n")
        
        store.stack.saveContext()
    }
}

extension String: TallyStoreType {
    
    public init?(dictionaryRepresentation:NSDictionary?) {
        guard let dictionary = dictionaryRepresentation,
            let value = dictionary["value"] as? String
            else { return nil }
        self = value
    }
    
    public func dictionaryRepresentation() -> NSDictionary {
        let representation = ["value": self]
        return representation as NSDictionary
    }
    
    public init?(coder: NSCoder) {
        guard let value = coder.decodeObject(forKey: "self") as? String
            else { return nil }
        self = value
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self, forKey: "self")
    }
}
