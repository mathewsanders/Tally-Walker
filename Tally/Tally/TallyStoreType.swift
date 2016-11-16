//
//  TallyStoreType.swift
//  Tally
//
//  Created by mat on 11/14/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation

public protocol TallyStoreType: class {
    
    associatedtype Item: Hashable
    typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    func incrementCount(for sequence: [Node<Item>])
    func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability]
    func distributions(excluding excludedItems: [Node<Item>]) -> [ItemProbability]
}

// Thunk
// https://gist.github.com/alonecuzzo/5bc4e19017b0aba66fe6
// http://krakendev.io/blog/generic-protocols-and-their-shortcomings
// https://realm.io/news/type-erased-wrappers-in-swift/

public class AnyTallyStore<Item> where Item: Hashable {
    
    public typealias ItemProbability = (probability: Double, item: Node<Item>)
    public typealias Nodes = [Node<Item>]
    
    private let _incrementCount: (Nodes) -> Void
    private let _itemProbabilities: (Nodes) -> [ItemProbability]
    private let _distributions: (Nodes) -> [ItemProbability]
    
    init<Store>(_ store: Store) where Store: TallyStoreType, Store.Item == Item {
        _incrementCount = store.incrementCount
        _itemProbabilities = store.itemProbabilities
        _distributions = store.distributions
    }
    
    public func incrementCount(for sequence: Nodes) {
        _incrementCount(sequence)
    }
    
    public func itemProbabilities(after sequence: Nodes) -> [ItemProbability] {
        return _itemProbabilities(sequence)
    }
    
    public func distributions(excluding excludedItems: Nodes = []) -> [ItemProbability] {
        return _distributions(excludedItems)
    }
}

public protocol TallyStoreNodeType {
    
    associatedtype Item: Hashable
    
    // get and set the number of occurances of this node
    var count: Double { get set }
    
    // get the node
    var node: Node<Item> { get }
    
    // get child nodes
    var childNodes: [Self] { get }
    
    // add a child
    func addChild(_: Self)
    
    // return an existing child node matching an item, or create a new child node with that item
    func childNode(with item: Node<Item>) -> Self
    
}

extension TallyStoreNodeType  {
    
    internal typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    mutating func incrementCount(for sequence: [Node<Item>]) {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            var child = childNode(with: item)
            child.incrementCount(for: tail)
            addChild(child)
        }
        else {
            count += 1
        }
    }
    
    func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability] {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            
            let child = childNode(with: item)
            return child.itemProbabilities(after: tail)
        }
            
        else { // tail is empty
            
            let total: Double = childNodes.reduce(0.0, { partial, child in
                return partial + child.count
            })
            
            return childNodes.map({ child in
                let prob = child.count / total
                return (probability: prob, item: child.node)
            })
        }
    }
    
    func distributions(excluding excludedItems: [Node<Item>] = []) -> [ItemProbability] {
        
        let total: Double = childNodes.reduce(0.0, { partial, child in
            if child.node.isBoundaryOrRoot { return partial }
            if excludedItems.contains(child.node) { return partial }
            return partial + child.count
        })
        
        return childNodes.flatMap { child in
            
            if child.node.isBoundaryOrRoot { return nil }
            if excludedItems.contains(child.node) { return nil }
            
            let prob = child.count / total
            return (item: child.node, probability: prob)
        }
    }
}