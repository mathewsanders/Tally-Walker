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
        
        let fileName = "data.plist"
        
        XCTAssertTrue(store.writeToDisk(at: fileName), "Model not written to disk")
        
        if let storeFromDisk = StringStore(fromFile: fileName) {
            
            let newModel = bridge.load(store: storeFromDisk)
            
            XCTAssertTrue(originalModel.ngram.size == newModel.ngram.size, "Ngram size does not match")
            XCTAssertTrue(originalModel.sequence == newModel.sequence, "Sequence type does not match")
            XCTAssertTrue(originalModel.distributions().count == newModel.distributions().count, "Number of model distributions do not match")
        }
        else {
            XCTFail("Failed to load store from disk")
        }
        
    }
    
    /// An implementation of a store for Strings.
    public struct StringStore: TallyStoreType {
        
        public var ngramType: NgramType
        public var sequence: TallySequenceType
        
        public typealias Id = String
        public typealias StringNode = Node<String>
        
        public typealias StoreItem = String
        
        public typealias NodeDetails = (node: Node<String>, count: Int, childIds: [Id])
        
        var data: [Id: [String : Any]]
        
        public var rootChildIds: [TallyStoreType.Id]
        
        func writeToDisk(at fileName: String) -> Bool {

            let storeDict: [String: Any] = [
                "ngramSize": ngramType.size,
                "sequenceType": sequence.rawValue,
                "rootChildIds": rootChildIds,
                "data": data
            ]
            
            let dict = storeDict as NSDictionary
  
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            let documentsDirectory = paths[0]
            let filePath = documentsDirectory + "/" + fileName
            
            print(filePath)
            
            return dict.write(toFile: filePath, atomically: false)
        }
        
        public init() {
            data = [:]
            ngramType = .bigram
            sequence = .continuousSequence
            rootChildIds = []
        }
        
        init?(fromFile fileName: String) {
            
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            let documentsDirectory = paths[0]
            let filePath = documentsDirectory + "/" + fileName
            
            if let storeDict = NSMutableDictionary(contentsOfFile: filePath) {
                data = storeDict.object(forKey: "data") as AnyObject as! [StoreTests.StringStore.Id : [String : Any]]
                
                let ngramSize = storeDict.object(forKey: "ngramSize") as! Int
                ngramType = NgramType.ngram(depth: ngramSize)
                
                let sequenceRawValue = storeDict.object(forKey: "sequenceType") as! Int
                sequence = TallySequenceType(rawValue: sequenceRawValue)!
                
                let childIds = storeDict.object(forKey: "rootChildIds") as! [String]
                rootChildIds = childIds
            }
            else { return nil }
        }
        
        public func get(id: Id) -> NodeDetails? {
            
            if let dict = data[id] {
                
                let value = dict["value"] as! String
                let count = dict["count"] as! Int
                let childIds = dict["childIds"] as! [String]
                
                if let node = node(from: value) {
                    return NodeDetails(node, count, childIds)
                }
            }
            return nil
        }
        
        public mutating func add(id: Id, value: (node: Node<String>, count: Int, childIds: [Id])) {
            if let str = storeValue(from: value.node) {
                
                let dict: [String : Any] = [
                    "value": str,
                    "count": value.count,
                    "childIds": value.childIds
                ]
                
                data[id] = dict
            }
        }
        
        private func storeValue(from node: Node<String>) -> String? {
            switch node {
            case .root: return nil
            case .sequenceEnd, .sequenceStart, .unseenTrailingItems, .unseenLeadingItems: return node.descriptor
            case .item(let value): return node.descriptor + value
            }
        }
        
        private func node(from storeValue: String) -> Node<String>? {
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
