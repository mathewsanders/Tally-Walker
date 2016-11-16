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
        return root.distributions(excluding: excludedItems)
    }
}

// MARK: -

fileprivate final class MemoryNode<Item>: TallyStoreNodeType where Item: Hashable {
    
    internal typealias Children = [Node<Item>: MemoryNode<Item>]
    
    internal let node: Node<Item>
    internal var count: Double = 0
    internal var children: Children = [:]
    
    required init(withItem node: Node<Item> = .root) {
        self.node = node
    }
    
    public func addChild(_ child: MemoryNode<Item>) {
        children[child.node] = child
    }
    
    public var childNodes: [MemoryNode<Item>]{
        return Array(children.values)
    }
    
    public func childNode(with item: Node<Item>) -> MemoryNode<Item> {
        return children[item] ?? MemoryNode<Item>(withItem: item)
    }
}
