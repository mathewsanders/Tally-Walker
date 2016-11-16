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

public class AnyTallyStore<Item>: TallyStoreType where Item: Hashable {
    
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
