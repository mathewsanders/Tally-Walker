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
        
        var model = Tally<String>()
        var store = TallyCoreDataStore<String>()
        
        model.delegate = AnyTallyStore(store)
        
        model.observe(sequence: ["hello", "world"])
        
    }
    
    
}

extension String: TallyStoreType {
    
    init?(dictionaryRepresentation:NSDictionary?) {
        guard let dictionary = dictionaryRepresentation,
            let value = dictionary["value"] as? String
            else { return nil }
        self = value
    }
    
    func dictionaryRepresentation() -> NSDictionary {
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
