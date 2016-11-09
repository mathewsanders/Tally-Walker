//
//  StoreTests.swift
//  Tally
//
//  Created by Mathew Sanders on 11/8/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import XCTest
@testable import Tally

class StoreTests: XCTestCase {
    
    var originalModel = Tally<String>(ngram: .trigram)
    
    override func setUp() {
        super.setUp()
        originalModel.observe(sequence: ["the", "cat", "in", "the", "hat"])
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testStoreAndExtract() {
        let bridge = TallyBridge<String, StringStore>()
        let store = bridge.load(model: originalModel)
        
        let newModel = bridge.load(store: store)
        
        XCTAssertTrue(originalModel.ngram.size == newModel.ngram.size, "Ngram size does not match")
        XCTAssertTrue(originalModel.sequence == newModel.sequence, "Sequence type does not match")
    }
    
    public struct StringStore: TallyStoreType {
        
        public var ngramType: NgramType = .bigram
        public var sequence: TallySequenceType = .continuousSequence
        
        public typealias StoreItem = String
        public typealias StringNode = Node<String>
        public typealias Count = Int
        public typealias Id = String
        public typealias NodeDetails = (node: Node<String>, count: Int, childIds: [Id])
        
        var data: [Id: (StoreItem, Count, [Id])] = [:]
        public var ngramFirstItemIds: [TallyStoreType.Id] = []
        
        public init() {
            
        }
        
        public func get(id: Id) -> NodeDetails? {
            
            if let result = data[id], let node = node(from: result.0) {
                
                let count = result.1
                let children = result.2
                
                return NodeDetails(node, count, children)
            }
            return nil
        }
        
        public mutating func add(id: Id, value: (node: Node<String>, count: Int, childIds: [Id])) {
            if let str = storeValue(from: value.node) {
                data[id] = (str, value.count, value.childIds)
            }
        }
        
        func storeValue(from node: Node<String>) -> String? {
            switch node {
            case .root: return nil
            case .sequenceEnd, .sequenceStart, .unseenTrailingItems, .unseenLeadingItems: return node.descriptor
            case .item(let value): return node.descriptor + value
            }
        }
        
        public func node(from storeValue: String) -> Node<String>? {
            switch storeValue {
            case Node<String>.unseenLeadingItems.descriptor: return Node<String>.unseenLeadingItems
            case Node<String>.unseenTrailingItems.descriptor: return Node<String>.unseenTrailingItems
            case Node<String>.sequenceStart.descriptor: return Node<String>.sequenceStart
            case Node<String>.sequenceEnd.descriptor: return Node<String>.sequenceEnd
            case Node<String>.root.descriptor: return nil
                
            default: // should be an item, check to see if it's got the correct item descriptor prefix
                let prefix = Node<String>.item("").descriptor
                if storeValue.hasPrefix(prefix) {
                    let literalStr = storeValue.substring(from: prefix.endIndex)
                    return Node<String>.item(literalStr)
                }
                return nil
            }
        }
    }
    
}
