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

// TODO: Rename `distributions` function.

/**
 Defines implementation requirements to act as a store for a `Tally` model.
 
 **Note** You *can* directly implement this, but for most situations it's probably easier to instead
 implement `TallyStoreTreeNode` which then provides default implentation through a protocol extension.
 */
public protocol TallyStoreType {
    
    associatedtype Item: Hashable
    
    /// A tuple that combines an probability (expected to be within the range of 0.0 and 1.0) and a node.
    typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    /**
     Increase the count of this sequence by one.
     
     The store needs to have an interface where given an n-gram, represented as a sequence of nodes, that 
     the count for that n-gram is increased.
     
     - parameter ngram: An array of nodes representing the n-gram.
     */
    func incrementCount(for ngram: [Node<Item>])
    
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
    func incrementCount(for ngram: [Node<Item>], completed: (() -> Void)?)
    
    /**
     Return the probability of items to complete an n-gram.
     
     - parameter sequence: An array of nodes representing the n-gram.
     - returns: An array of `ItemProbability`.
     */
    func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability]
    
    func distributions(excluding excludedItems: [Node<Item>]) -> [ItemProbability]
    
}

extension TallyStoreType {
    public func incrementCount(for ngram: [Node<Item>], completed: (() -> Void)?) {
        print("WARNING: Using default implementation of incrementCount with closure.")
        incrementCount(for: ngram)
        completed?()
    }
}

/// Any object that implements the `TallyStoreType` protocol can be used as a store for a `Tally` model,
/// however the recommended approach is to create a tree structure where nodes in the tree represent
/// the elements that make up n-grams.
/// 
/// For example, a model that represents the following five bigrams: (A B), (A C), (B C), (B D), (B D)
/// would in turn be represented by a tree structure like this:
///
/// ~~~
///         *root
///       /       \
///      /         \
///     A(2)        B(3)
///    / \         / \
///   /   \       /   \
///  B(1)  C(1)  C(1)  D(2)
/// ~~~
/// 
/// Each tree node includes the element of the n-gram that it represents, a count to represent that
/// the frequency of of n-gram elements.
///
/// Some expectations about representing n-grams in this tree structure: 
/// - If a node has child nodes, it's count should match the sum of it's direct children counts.
/// - The depth of the tree should match the size of the n-gram. For example: a bigram sholud have two
///   levels below the root, a trigram have three levels below the root.
/// 
/// Rather than implement the complexity of `TallyStoreType` directly, it is recommended to instead
/// implemenent the less complex `TallyStoreTreeNode` protocol. Doing so provides default implementation 
/// of `TallyStoreType` requirements. You will still need to create a lightweight `TallyStoreType` that
/// acts as a proxy for the root node.
///
/// See `MemoryTallyStore` for the most concise example of this appraoch.
///
public protocol TallyStoreTreeNode {
    
    associatedtype Item: Hashable
    
    /// The element of an n-gram represented by this tree node.
    var node: Node<Item> { get }
    
    /// The number of times that this node occurs within the tree.
    /// When initalizing a new node, you should set the initial value to be 0.0.
    var count: Double { get set }
    
    /// Return the sequence of child nodes of this node.
    ///
    /// For implementations where it is expensive to get the children of a node in a single step,
    /// it's recommended to return a lazy sequence.
    var childNodes: AnySequence<Self> { get }
    
    /// Returns the child this node that represents the given item or nil if no such child exists.
    /// 
    /// - parameter item: The item used to identify which child node to return.
    /// - returns: The child node that represents an item, or nil if no child node exists.
    func findChildNode(with item: Node<Item>) -> Self?

    /// Add a child node that represents an item.
    ///
    /// This method is only called with it's known that a child node representing this
    /// item does not exist, so to improve performance you should not perform this
    /// check in your own implementation.
    ///
    /// - parameter item: The item to represent with the child node.
    /// - returns: The newly created child node.
    func makeChildNode(with item: Node<Item>) -> Self
    
}

extension TallyStoreTreeNode  {
    
    internal typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    mutating func incrementCount(for ngram: [Node<Item>]) {
        
        let (_, tail) = ngram.headAndTail()
        
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

// Thunk
// https://gist.github.com/alonecuzzo/5bc4e19017b0aba66fe6
// http://krakendev.io/blog/generic-protocols-and-their-shortcomings
// https://realm.io/news/type-erased-wrappers-in-swift/

///
/// A type-erased Tally store.
///
/// An instance of AnyTallyStore forwards its operations to an underlying base store having the same Item type,
/// hiding the specifics of the underlying store.
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
    
    public func incrementCount(for ngram: [Node<Item>]) {
        _incrementCount(ngram)
    }
    
    public func incrementCount(for ngram: [Node<Item>], completed closure: (() -> Void)? = nil) {
        _incrementCountWithCompletion(ngram, closure)
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [ItemProbability] {
        return _itemProbabilities(sequence)
    }
    
    public func distributions(excluding excludedItems: [Node<Item>] = []) -> [ItemProbability] {
        return _distributions(excludedItems)
    }
}
