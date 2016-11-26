// TallyStoreType.swift
//
// Copyright (c) 2016 Mathew Sanders
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

// TODO: Consider using ngram instead of sequence as function labels
// TODO: Rename `distributions` function.

/**
 Defines implementation requirements to act as a store for a `Tally` model.
 
 **Note** You *can* directly implement this, but for most situations it's probably easier to instead
 implement `TallyStoreNodeType` which then provides default implentation through a protocol extension.
 */
public protocol TallyStoreType {
    
    associatedtype Item: Hashable
    
    /// A tuple that combines an probability (expected to be within the range of 0.0 and 1.0) and a node.
    typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    /**
     Increase the count of this sequence by one.
     
     The store needs to have an interface where given an n-gram, represented as a sequence of nodes, that 
     the count for that n-gram is increased.
     
     - parameter sequence: An array of nodes representing the n-gram.
     */
    func incrementCount(for sequence: [Node<Item>])
    
    /**
     Asynchronously increase the count of this sequence by one.
     
     The store needs to have an interface where given an n-gram, represented as a sequence of nodes, that
     the count for that n-gram is increased.
     
     For stores with internal implementations where this process occurs asynchronously, this method should be 
     implemented so that the completed closure is executed when the asynchronous process is completed.
     
     - parameters:
        - sequence: An array of nodes representing the n-gram.
        - completed: The closure object with contents that will be executed once the count increment is done.
     */
    func incrementCount(for sequence: [Node<Item>], completed: (() -> Void)?)
    
    /**
     Return the probability of items to complete an n-gram.
     
     - parameter sequence: An array of nodes representing the n-gram.
     - returns: An array of `ItemProbability`.
     */
    func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability]
    
    func distributions(excluding excludedItems: [Node<Item>]) -> [ItemProbability]
    
}

extension TallyStoreType {
    public func incrementCount(for sequence: [Node<Item>], completed: (() -> Void)?) {
        print("WARNING: Using default implementation of incrementCount with closure.")
        incrementCount(for: sequence)
        completed?()
    }
}

// Thunk
// https://gist.github.com/alonecuzzo/5bc4e19017b0aba66fe6
// http://krakendev.io/blog/generic-protocols-and-their-shortcomings
// https://realm.io/news/type-erased-wrappers-in-swift/

/**
 A type-erased Tally store.
 
 An instance of AnyTallyStore forwards its operations to an underlying base store having the same Item type, 
 hiding the specifics of the underlying store.
 */
public class AnyTallyStore<Item>: TallyStoreType where Item: Hashable {
    
    public typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    private let _incrementCount: ([Node<Item>]) -> Void
    private let _incrementCountWithCompletion: ([Node<Item>], (() -> Void)?) -> Void
    private let _itemProbabilities: ([Node<Item>]) -> [ItemProbability]
    private let _distributions: ([Node<Item>]) -> [ItemProbability]
    
    public init<Store>(_ store: Store) where Store: TallyStoreType, Store.Item == Item {
        _incrementCount = store.incrementCount
        _itemProbabilities = store.itemProbabilities
        _distributions = store.distributions
        _incrementCountWithCompletion = store.incrementCount
    }
    
    public func incrementCount(for sequence: [Node<Item>]) {
        _incrementCount(sequence)
    }
    
    public func incrementCount(for sequence: [Node<Item>], completed closure: (() -> Void)? = nil) {
        _incrementCountWithCompletion(sequence, closure)
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability] {
        return _itemProbabilities(sequence)
    }
    
    public func distributions(excluding excludedItems: [Node<Item>] = []) -> [ItemProbability] {
        return _distributions(excludedItems)
    }
}

/**
 Defines the implementation requirements in creating a `TallyStoreTypeNode`, which in turn is
 the recomended approach in creating a `TallyStoreType`.
 
 This represents n-grams of type `Item` as a tree structure of type `Node<Item>`.
 */
public protocol TallyStoreNodeType {
    
    associatedtype Item: Hashable
    
    /// Return the `Node` represented by this object.
    var node: Node<Item> { get }
    
    /// Represents the number of times that `node` has been seen.
    var count: Double { get set }
    
    /// Return a sequence of child nodes in the tree.
    /// For implementations where it is expensive to get the children of a node, 
    /// it's recommended to return a lazy sequence.
    var childNodes: AnySequence<Self> { get }
    
    /// Return a reference to a child node that matches an item (or nil if no such child exists).
    func findChildNode(with item: Node<Item>) -> Self?

    /// Create a new node, add it to this nodes children, and return a reference.
    func makeChildNode(with item: Node<Item>) -> Self
    
}

// TODO: Consider moving default implementation into this extension rather than the node itself.
// extension TallyStoreType where Item: TallyStoreNodeType { }

extension TallyStoreNodeType  {
    
    internal typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    mutating func incrementCount(for sequence: [Node<Item>]) {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            var child = findChildNode(with: item) ?? makeChildNode(with: item)
            child.incrementCount(for: tail)
        }
        else {
            count += 1
        }
    }
    
    func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability] {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            
            if let child = findChildNode(with: item) {
                return child.itemProbabilities(after: tail)
            }
            else { return [] }
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
            return (probability: prob, item: child.node)
        }
    }
}
