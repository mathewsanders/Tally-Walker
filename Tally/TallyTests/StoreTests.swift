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
    public struct StringStore: TallyFlatStoreType {
        
        public typealias Id = String
        public typealias StringNode = Node<String>
        public typealias StoreItem = String
        public typealias NodeDetails = (node: Node<String>, count: Int, childIds: [Id])
        
        public var sequenceType: TallySequenceType
        public var ngramType: NgramType
        public var rootChildIds: [TallyFlatStoreType.Id]
        
        internal var data: [Id: [String : Any]]
        
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
                let sequenceRawValue = storeDict.object(forKey: TallyFlatStoreKeys.sequenceTypeValue) as? Int,
                let sequenceType = TallySequenceType(rawValue: sequenceRawValue),
                let ngramSize = storeDict.object(forKey: TallyFlatStoreKeys.ngramSize) as? Int,
                let rootChildIds = storeDict.object(forKey: TallyFlatStoreKeys.rootChildIds) as? [StoreTests.StringStore.Id],
                let data = storeDict.object(forKey: TallyFlatStoreKeys.data) as? [StoreTests.StringStore.Id : [String : Any]]
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
                TallyFlatStoreKeys.ngramSize : ngramType.size,
                TallyFlatStoreKeys.sequenceTypeValue: sequenceType.rawValue,
                TallyFlatStoreKeys.rootChildIds: rootChildIds,
                TallyFlatStoreKeys.data: data
            ]
            
            let dict = storeDict as NSDictionary
            
            return dict.write(toFile: filePath, atomically: false)
        }
        
        public func get(id: Id) -> NodeDetails? {
            guard
                let nodeDetails = data[id],
                let textRepresentation = nodeDetails[TallyFlatStoreKeys.NodeDetails.textRepresentation] as? String,
                let node = node(from: textRepresentation),
                let count = nodeDetails[TallyFlatStoreKeys.NodeDetails.count] as? Int,
                let childIds = nodeDetails[TallyFlatStoreKeys.NodeDetails.childIds] as? [String]
                else { return nil }
            
            return NodeDetails(node, count, childIds)
        }
        
        public mutating func add(id: Id, value: (node: Node<String>, count: Int, childIds: [Id])) {
            guard let nodeTextRepresentation = textRepresentation(from: value.node)
                else { return }
            
            let nodeDetails: [String : Any] = [
                TallyFlatStoreKeys.NodeDetails.textRepresentation: nodeTextRepresentation,
                TallyFlatStoreKeys.NodeDetails.count: value.count,
                TallyFlatStoreKeys.NodeDetails.childIds: value.childIds
            ]
            
            data[id] = nodeDetails
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

extension String: NodeRepresentableWithTextType {
    public init?(_ text: String) {
        self = text
    }
    
    public var textValue: String {
        return self.description
    }
}
