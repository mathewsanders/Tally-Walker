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
    
    /// Takes a model, saves the model to a local file, then loads a new model from that file and looks for distinguishing features to check if they are the same 
    func testStoreAndExtract() {
        
        let bridge = TallyBridge<String, StringStore>()
        let store = bridge.load(model: originalModel)
        
        let plistName = "data"
        
        XCTAssertTrue(store.save(to: plistName), "Model not saved to file")
        
        guard let storeFromFile = StringStore(from: plistName) else {
            XCTFail("Failed to load store from disk")
            return
        }
        
        let newModel = bridge.load(store: storeFromFile)
        
        XCTAssertTrue(originalModel.ngram.size == newModel.ngram.size, "Ngram size does not match")
        XCTAssertTrue(originalModel.sequence == newModel.sequence, "Sequence type does not match")
        XCTAssertTrue(originalModel.distributions().count == newModel.distributions().count, "Number of model distributions do not match")
        XCTAssertTrue(originalModel.itemProbabilities(after: "the").count == 2, "Number of item probabilities for the item 'the' is not expected")
        XCTAssertTrue(originalModel.itemProbabilities(after: "the")[0].probability == 0.5, "Value for item probabilities for the item 'the' is not expected")
        
    }
    
    /// An implementation of a store for Tally<String> model that stores information to a .plist.
    public struct StringStore: TallyStoreType {
        
        public typealias Id = String
        public typealias StringNode = Node<String>
        public typealias StoreItem = String
        public typealias NodeDetails = (node: Node<String>, count: Int, childIds: [Id])
        
        public var sequenceType: TallySequenceType
        public var ngramType: NgramType
        public var rootChildIds: [TallyStoreType.Id]
        
        internal var data: [Id: [String : Any]]
        
        struct KeyName {
            static let sequenceTypeValue = "sequenceTypeValue"
            static let ngramSize = "ngramSize"
            static let rootChildIds = "rootChildIds"
            static let data = "data"
            
            struct NodeDetails {
                static let value = "NodeValue"
                static let count = "NodeCount"
                static let childIds = "NodeChildIds"
            }
        }
        
        public init(sequenceType: TallySequenceType, ngramType: NgramType, rootChildIds: [Id]) {
            self.sequenceType = sequenceType
            self.ngramType = ngramType
            self.rootChildIds = rootChildIds
            data = [:] // data will be loaded incrementally with calls to `add`
        }
        
        /// Attempts to load a store from a local .plist file.
        init?(from plistName: String) {
            
            let filePath = StringStore.getFilePath(for: plistName)
            
            guard
                let storeDict = NSMutableDictionary(contentsOfFile: filePath),
                let sequenceRawValue = storeDict.object(forKey: KeyName.sequenceTypeValue) as? Int,
                let sequenceType = TallySequenceType(rawValue: sequenceRawValue),
                let ngramSize = storeDict.object(forKey: KeyName.ngramSize) as? Int,
                let rootChildIds = storeDict.object(forKey: KeyName.rootChildIds) as? [StoreTests.StringStore.Id],
                let data = storeDict.object(forKey: KeyName.data) as? [StoreTests.StringStore.Id : [String : Any]]
                else { return nil }
            
            self.rootChildIds = rootChildIds
            self.sequenceType = sequenceType
            ngramType = NgramType.ngram(depth: ngramSize)
            self.data = data
        }
        
        /// Attempts to save a store to a local .plist file
        /// returns: true if save to file was successful.
        func save(to plistName: String) -> Bool {
            
            let filePath = StringStore.getFilePath(for: plistName)
            print(filePath)
            
            let storeDict: [String: Any] = [
                KeyName.ngramSize : ngramType.size,
                KeyName.sequenceTypeValue: sequenceType.rawValue,
                KeyName.rootChildIds: rootChildIds,
                KeyName.data: data
            ]
            
            let dict = storeDict as NSDictionary
            
            return dict.write(toFile: filePath, atomically: false)
        }
        
        public func get(id: Id) -> NodeDetails? {
            guard
                let dict = data[id],
                let value = dict[KeyName.NodeDetails.value] as? String,
                let count = dict[KeyName.NodeDetails.count] as? Int,
                let childIds = dict[KeyName.NodeDetails.childIds] as? [String],
                let node = node(from: value)
                else { return nil }
            
            return NodeDetails(node, count, childIds)
        }
        
        public mutating func add(id: Id, value: (node: Node<String>, count: Int, childIds: [Id])) {
            if let str = storeValue(from: value.node) {
                let dict: [String : Any] = [
                    KeyName.NodeDetails.value: str,
                    KeyName.NodeDetails.count: value.count,
                    KeyName.NodeDetails.childIds: value.childIds
                ]
                data[id] = dict
            }
        }
        
        /// Translates a node into a string value that can be stored
        /// example: the literal node `hello` is transformed into something like "Node.Item:Hello"
        /// the node `unseenLeadingItems` is transformed into something like "Node.unseenLeadingItems"
        private func storeValue(from node: Node<String>) -> String? {
            switch node {
            case .root: return nil
            case .sequenceEnd, .sequenceStart, .unseenTrailingItems, .unseenLeadingItems: return node.descriptor
            case .item(let value): return node.descriptor + value
            }
        }
        
        /// Translates a string value back into a node, the reverse of `storeValue(from: Node<String>)`
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
        
        /// helper function to get local file path for plist
        private static func getFilePath(for plistName: String) -> String {
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            let documentsDirectory = paths[0]
            let filePath = documentsDirectory + "/" + plistName + ".plist"
            return filePath
        }
    }
    
}
