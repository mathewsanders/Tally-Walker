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
public protocol TallyStoreType {
    
    associatedtype StoreItem: Hashable
    
    /// A unique reference representing a node.
    typealias Id = String // using UUID
    
    /// A tuple that represents a node in a tree representing a structure of ngrams.
    /// - `node` is a wrapper for the item in the ngram which may represent a literal item, or also a marker to represent the start, or end of a sequence. It is up to the implementation to ensure that these markers are suitably accounted for in the store.
    /// - `count` is an integer representing the number of occurances of the node.
    /// - `childIds` an array of ids of children of this node.
    typealias StoreValue = (node: Node<StoreItem>, count: Int, childIds: [Id])
    
    /// Ids for children of the root node.
    var rootChildIds: [Id] { get set }
    
    /// Add information about a node to the store
    ///
    /// - parameter id: the Id of the node, used as an index.
    /// - parameter value: the node, number of occurances, and childIds of the node.
    mutating func add(id: Id, value: StoreValue)
    
    /// Get the node, number of occurances, and Ids of child nodes for the node with the id
    /// Returns nil if no node found in the store with that id.
    /// - parameter id: the Id of the node to retrieve.
    func get(id: Id) -> StoreValue?
    
    /// The type of sequence of the model that this store holds.
    var sequence: TallySequenceType { get set }
    
    /// The size of the ngram of the model that this store holds.
    var ngramType: NgramType { get set }
    
    /// The store needs to be initalizable without any parameters.
    init()
    
}

extension TallyStoreType {
    init() {
        self.init()
    }
}

/// A generic object that acts as a bridge between a Tally model and a compatable object that implements `TallyStoreType`.
/// Creating a bridge allows a model to be exported into a store, and vice versa.
public struct TallyBridge<Item: Hashable, Store: TallyStoreType> where Store.StoreItem == Item {

    /// Loads a model from a store.
    /// - parameter store: An object of `TallyStoreType` storing information about a model
    /// - returns: A model made from information in the store.
    public func load(store: Store) -> Tally<Item> {
        
        var model = Tally<Item>(representing: store.sequence, ngram: store.ngramType)
        var rootChildren: [Node<Item>: NodeEdges<Item>] = [:]
        
        store.rootChildIds.flatMap({ id in
            loadEdge(with: id, from: store, to: model)
        }).forEach({ edge in
            rootChildren[edge.node] = edge
        })
        
        let root = NodeEdges<Item>(node: Node<Item>.root, count: 0, children: rootChildren)
        
        model.root = root
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
        
        var store = Store()
        store.ngramType = model.ngram
        store.sequence = model.sequence
        store.rootChildIds = model.root.childIds
        
        var queue = model.root.childIds
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

