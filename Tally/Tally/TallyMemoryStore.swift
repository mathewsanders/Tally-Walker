//
//  TallyMemoryStore.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation

class MemoryTallyStore<MemoryItem: Hashable> : TallyStoreDelegate {
    
    typealias Item = MemoryItem
    
    public typealias Root = NodeEdges<Item>
    public var root: Root
    
    init() {
        self.root = NodeEdges(withItem: .root)
    }
    
    public func incrementCount(for sequence: [Node<Item>]) {
        root.incrementCount(for: [root.node] + sequence)
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.itemProbabilities(after: [root.node] + sequence)
    }
    
    public func distributions(excluding excludedItems: [Node<Item>] = []) -> [(probability: Double, item: Node<Item>)] {
        
        let total: Double = root.children.values.reduce(0.0, { partial, child in
            if child.node.isBoundaryOrRoot { return partial }
            if excludedItems.contains(child.node) { return partial }
            return partial + child.count
        })
        
        return root.children.values.flatMap { child in
            
            if child.node.isBoundaryOrRoot { return nil }
            if excludedItems.contains(child.node) { return nil }
            
            let prob = child.count / total
            return (item: child.node, probability: prob)
        }
    }
}

// MARK: -

public struct NodeEdges<Item: Hashable> {
    
    internal typealias Children = [Node<Item>: NodeEdges<Item>]
    internal typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    internal let node: Node<Item>
    internal var count: Double = 0
    internal var children: Children = [:]
    internal var id: String = UUID().uuidString
    
    internal typealias Nodes = [Node<Item>]
    
    init(withItem node: Node<Item> = .root) {
        self.node = node
    }
    
    init(node: Node<Item>, count: Double, children: Children) {
        self.node = node
        self.count = count
        self.children = children
    }
    
    internal var childIds: [String] {
        return children.values.map({ $0.id })
    }
    
    mutating func incrementCount(for sequence: Nodes) {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            var child = children[item] ?? NodeEdges<Item>(withItem: item)
            child.incrementCount(for: tail)
            children[item] = child
        }
        else {
            count += 1
        }
    }
    
    func itemProbabilities(after sequence: Nodes) -> [ItemProbability] {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            if let child = children[item] {
                return child.itemProbabilities(after: tail)
            }
        }
            
            
            
            
            
        else { // tail is empty
            let total: Double = children.values.reduce(0.0, { partial, child in
                return partial + child.count
            })
            
            return children.values.map({ child in
                let prob = child.count / total
                return (probability: prob, item: child.node)
            })
        }
        return []
    }
}
