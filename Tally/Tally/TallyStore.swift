//
//  TallyStore.swift
//  Tally
//
//  Created by Mathew Sanders on 11/8/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation

/// Defines the implementation needed to create a store to represent a `Tally` model.
/// The internal structure of a `Tally` model is a tree. A `TallyStoreType` flattens this tree structure into a simple
/// list of all nodes in the tree which is easier to represent in a textual format.
public protocol TallyFlatStoreType {
    
    associatedtype StoreItem: Hashable
    
    /// A unique reference representing a node.
    typealias Id = String
    
    /// A tuple that represents a node in a tree representing a structure of ngrams.
    /// - `node` is a wrapper for the item in the ngram which may represent a literal item, or also a marker
    /// to represent the start, or end of a sequence. It is up to the implementation to ensure that these
    /// markers are suitably accounted for in the store.
    /// - `count` is an integer representing the number of occurrences of the node.
    /// - `childIds` an array of ids of children of this node.
    typealias StoreValue = (node: Node<StoreItem>, count: Int, childIds: [Id])
    
    /// Initialize a store with appropriate settings, and the ids of root node children.
    /// It's expected that the store is filled with a subsequent call to `add(id: Id, value: StoreValue)`
    /// for each item in the model.
    init(sequenceType: TallySequenceType, ngramType: NgramType, rootChildIds: [Id])
    
    /// Add information about a node to the store.
    ///
    /// - parameter id: the Id of the node, used as an index.
    /// - parameter value: the node, number of occurrences, and childIds of the node.
    mutating func add(id: Id, value: StoreValue)
    
    /// Get the node, number of occurrences, and Ids of child nodes for the node with the id.
    /// Returns nil if no node found in the store with that id.
    /// - parameter id: the Id of the node to retrieve.
    func get(id: Id) -> StoreValue?
    
    /// You should not need to call any of the following properties yourself. They are expected to be used
    /// by `TallyBridge` as part of the process of loading a model from a store.
    
    /// The type of sequence of the model that this store holds.
    var sequenceType: TallySequenceType { get }
    
    /// The size of the ngram of the model that this store holds.
    var ngramType: NgramType { get }
    
    /// Ids for children of the root node.
    var rootChildIds: [Id] { get }
}

/// A generic object that acts as a bridge between a Tally model and a compatable object that implements `TallyStoreType`.
/// Creating a bridge allows a model to be exported into a store, and vice versa.
public struct TallyBridge<Item: Hashable, Store: TallyFlatStoreType> where Store.StoreItem == Item {

    /// Loads a model from a store.
    /// - parameter store: An object of `TallyStoreType` storing information about a model
    /// - returns: A model made from information in the store.
    public func load(store: Store) -> Tally<Item> {
        
        var model = Tally<Item>(representing: store.sequenceType, ngram: store.ngramType)
        var rootChildren: [Node<Item>: NodeEdges<Item>] = [:]
        
        store.rootChildIds.flatMap({ id in
            loadEdge(with: id, from: store, to: model)
        }).forEach({ edge in
            rootChildren[edge.node] = edge
        })
        
        let root = NodeEdges<Item>(node: Node<Item>.root, count: 0, children: rootChildren)
        
        model.store.root = root
        
        //model.root = root
        return model
    }
    
    private func loadEdge(with id: String, from store: Store, to model: Tally<Item>) -> NodeEdges<Item>? {
        
        if let nodeDetails = store.get(id: id) {
            
            let edges = nodeDetails.childIds.flatMap({ childId in
                return loadEdge(with: childId, from: store, to: model)
            })
            
            var children: [Node<Item>: NodeEdges<Item>] = [:]
            
            edges.forEach({ edge in
                children[edge.node] = edge
            })
            
            if children.isEmpty {
                let endNode = model.nodeForEnd
                let endNodeEdges = NodeEdges<Item>(node: endNode, count: nodeDetails.count, children: [:])
                
                children[endNode] = endNodeEdges
            }
            
            let edge = NodeEdges<Item>(node: nodeDetails.node, count: nodeDetails.count, children: children)
            return edge
        }
        
        return nil
    }
    
    /// Loads a store from a model.
    /// - parameter model: The `Tally` model to import into a store.
    /// - returns: An object conforming to `TallyStoreType` protocol.
    public func load(model: Tally<Item>) -> Store {
        
        //var store = Store(sequenceType: model.sequence, ngramType: model.ngram, rootChildIds: model.root.childIds)
        var store = Store(sequenceType: model.sequence, ngramType: model.ngram, rootChildIds: model.store.root.childIds)
        
        var queue = store.rootChildIds
        var seenIds: [Tally<Item>.Id] = []
        
        while !queue.isEmpty {
            
            let id = queue.removeFirst()
            
            seenIds.append(id)
            
            if let nodeDetails = model.nodeDetails(forId: id) {
                
                store.add(id: id, value: nodeDetails)
                
                nodeDetails.childIds.forEach({ childId in
                    if !seenIds.contains(childId) {
                        queue.append(childId)
                    }
                })
            }
        }
        return store
    }
}

/// Suggested keys for use in the implementation of a TallyFlatStore object.
/// Your implementation does not need to use these same keys, but it should have an equivalent set of keys.
public struct TallyFlatStoreKeys {
    
    static let sequenceTypeValue = "Model.sequenceTypeValue"
    static let ngramSize = "Model.ngramSize"
    static let rootChildIds = "Model.rootChildIds"
    static let data = "Model.data"
    
    struct NodeDetails {
        static let textRepresentation = "Node.TextRepresentation"
        static let count = "Node.Count"
        static let childIds = "Node.ChildIds"
    }
    
    struct NodePrefix {
        static let root = "Node.Root"
        static let sequenceStart = "Node.SequenceStart"
        static let sequenceEnd = "Node.SequenceEnd"
        static let unseenLeadingItems = "Node.UnseenLeadingItems"
        static let unseenTrailingItems = "Node.UnseenTrailingItems"
        static let item = "Node.Literal:"
    }
}

/// If your Tally model is based around items that are also of the type `NodeRepresentableWithTextType` then your implementation of
/// `TallyFlatStoreType` for this type include two convenience methods for the safe translation from a node to a text representation
/// and vice versa.
///
/// This helps jump-start your implementation of `TallyFlatStoreType` leaving you to implement the mechanics of structuring data 
/// for your persistant store.
public protocol NodeRepresentableWithTextType {
    
    /// Initalize the item through a literal text value.
    init?(_ text: String)
    
    /// return a text value of a node.
    var textValue: String { get }
}

public extension TallyFlatStoreType where StoreItem: Hashable, StoreItem: NodeRepresentableWithTextType {
    
    /// Get the text representation of a node.
    internal func textRepresentation(from node: Node<StoreItem>) -> String? {
        switch node {
        case .root: return nil
        case .sequenceEnd: return TallyFlatStoreKeys.NodePrefix.sequenceEnd
        case .sequenceStart: return TallyFlatStoreKeys.NodePrefix.sequenceStart
        case .unseenTrailingItems: return TallyFlatStoreKeys.NodePrefix.unseenTrailingItems
        case .unseenLeadingItems: return TallyFlatStoreKeys.NodePrefix.unseenLeadingItems
        case .item(let value): return TallyFlatStoreKeys.NodePrefix.item + value.textValue
        }
    }
    
    /// Get the node from a text representation.
    internal func node(from textRepresentation: String) -> Node<StoreItem>? {
        switch textRepresentation {
        case TallyFlatStoreKeys.NodePrefix.unseenLeadingItems: return Node<StoreItem>.unseenLeadingItems
        case TallyFlatStoreKeys.NodePrefix.unseenTrailingItems: return Node<StoreItem>.unseenTrailingItems
        case TallyFlatStoreKeys.NodePrefix.sequenceStart: return Node<StoreItem>.sequenceStart
        case TallyFlatStoreKeys.NodePrefix.sequenceEnd: return Node<StoreItem>.sequenceEnd
        case TallyFlatStoreKeys.NodePrefix.root: return nil
            
        default: // should be an item, check to see if it's got the correct item descriptor prefix
            
            let prefix = TallyFlatStoreKeys.NodePrefix.item
            guard textRepresentation.hasPrefix(prefix) else { return nil }

            let literalStr = textRepresentation.substring(from: prefix.endIndex)
            guard let storeItem = StoreItem(literalStr) else { return nil }
            
            return Node<StoreItem>.item(storeItem)
        }
    }
}
