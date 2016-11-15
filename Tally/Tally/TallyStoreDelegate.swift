//
//  TallyStoreDelegate.swift
//  Tally
//
//  Created by mat on 11/14/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation

public protocol TallyStoreDelegate: class {
    
    associatedtype Item: Hashable
    typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    var root: NodeEdges<Item> { get set }
    
    func incrementCount(for sequence: [Node<Item>])
    func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability]
    
}

// http://krakendev.io/blog/generic-protocols-and-their-shortcomings

private extension TallyStoreDelegate {
    func setRoot(root: NodeEdges<Item>)  { self.root = root }
    func getRoot() -> NodeEdges<Item> { return root }
}

public class AnyTallyStore<I: Hashable>: TallyStoreDelegate {
    
    public typealias Item = I
    public typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    private let _incrementCount: ([Node<Item>]) -> Void
    private let _itemProbabilities: ([Node<Item>]) -> [ItemProbability]
    private let _getRoot: (Void) -> NodeEdges<Item>
    private let _setRoot: (NodeEdges<Item>) -> Void
    
    public var root: NodeEdges<Item> {
        get { return _getRoot() }
        set { return _setRoot(newValue) }
    }
    
    init<D: TallyStoreDelegate>(_ delegate: D) where D.Item == I {
        _incrementCount = delegate.incrementCount
        _itemProbabilities = delegate.itemProbabilities
        _getRoot = delegate.getRoot
        _setRoot = delegate.setRoot
    }
    
    public func incrementCount(for sequence: [Node<Item>]) {
        _incrementCount(sequence)
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability] {
        return _itemProbabilities(sequence)
    }
}

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
}

