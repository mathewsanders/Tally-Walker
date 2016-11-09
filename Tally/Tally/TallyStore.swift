//
//  TallyStore.swift
//  Tally
//
//  Created by Mathew Sanders on 11/8/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation

/// Defines implementation needed to create a TallyStore
public protocol TallyStoreType {
    
    associatedtype StoreItem: Hashable
    
    typealias Id = String // using UUID
    typealias StoreValue = (node: Node<StoreItem>, count: Int, childIds: [Id])
    
    var ngramFirstItemIds: [Id] { get set }
    
    mutating func add(id: Id, value: StoreValue)
    func get(id: Id) -> StoreValue?
    
    var sequence: TallySequenceType { get set }
    var ngramType: NgramType { get set }
    
    init()
    
}

// a convertor that takes a Tally model and store that use the same type and communicate with each other
//TODO: is there any reason why this couldn't be added into the Tally class
public struct TallyBridge<Item: Hashable, Store: TallyStoreType> where Store.StoreItem == Item {
    
    public init() {}
    
    public func load(store: Store) -> Tally<Item> {
        
        var model = Tally<Item>(representing: store.sequence, ngram: store.ngramType)
        
        var rootChildren: [Node<Item>: NodeEdges<Item>] = [:]
        
        store.ngramFirstItemIds.flatMap({ id in
            loadEdge(with: id, from: store, to: model)
        }).forEach({ edge in
            rootChildren[edge.node] = edge
        })
        
        let root = NodeEdges<Item>(node: Node<Item>.root, count: 0, children: rootChildren)
        
        print("load complete!")
        
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
    
    public func load(model: Tally<Item>) -> Store {
        
        var store = Store()
        store.ngramType = model.ngram
        store.sequence = model.sequence
        store.ngramFirstItemIds = model.ngramFirstItemIds()
        
        var queue = model.ngramFirstItemIds()
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

