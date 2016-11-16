//
//  TallyMemoryStore.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation

class MemoryTallyStore<Item>: TallyStoreType where Item: Hashable {
    
    private var root: MemoryNode<Item>
    
    init() {
        self.root = MemoryNode(withItem: .root)
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

fileprivate struct MemoryNode<Item> where Item: Hashable {
    
    internal typealias Children = [Node<Item>: MemoryNode<Item>]
    internal typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    internal let node: Node<Item>
    internal var count: Double = 0
    internal var children: Children = [:]
    internal var id: String = UUID().uuidString
    
    init(withItem node: Node<Item> = .root) {
        self.node = node
    }
    
    init(node: Node<Item>, count: Double, children: Children) {
        self.node = node
        self.count = count
        self.children = children
    }
    
    mutating func incrementCount(for sequence: [Node<Item>]) {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            var child = children[item] ?? MemoryNode<Item>(withItem: item)
            child.incrementCount(for: tail)
            children[item] = child
        }
        else {
            count += 1
        }
    }
    
    func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability] {
        
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
