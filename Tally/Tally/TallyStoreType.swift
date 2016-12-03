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

///
/// Defines implementation requirements to act as a store for a `Tally` model.
///
/// **Note** You *can* directly implement this, but for most situations it's probably easier to instead
/// implement `TallyStoreTreeNode` which then provides default implentation through a protocol extension.
public protocol TallyStoreType {
    
    associatedtype Item: Hashable
    
    typealias ElementProbabilities = [(probability: Double, element: NgramElement<Item>)]
    
    /// Increase the count of an ngram by one.
    ///
    /// - parameter ngram: An array of n-gram elements
    func incrementCount(for ngram: [NgramElement<Item>])
    
    ///  Asynchronously increase the count of an n-gram by one.
    ///
    ///  For stores with internal implementations where this process occurs asynchronously, this method should be
    ///  implemented so that the completed closure is executed when the asynchronous process is completed.
    ///
    ///  - parameters:
    ///     - ngram: An array of n-gram elements.
    ///     - completed: The closure object with contents that will be executed once the process to 
    ///       increment the n-gram count is completed.
    func incrementCount(for ngram: [NgramElement<Item>], completed: (() -> Void)?)
    
    /// Return the probability of elements to complete an n-gram.
    ///
    /// - parameter elements: An array of n-gram elements representing an incomplete n-gram.
    /// - returns: An array containing possible elements to com
    func nextElement(following elements: [NgramElement<Item>]) -> ElementProbabilities
    
    func distributions(excluding excludedElements: [NgramElement<Item>]) -> ElementProbabilities
    
}

extension TallyStoreType {
    public func incrementCount(for ngram: [NgramElement<Item>], completed: (() -> Void)?) {
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
///        /     \
///       /       \
///      /         \
///     A(2)        B(3)
///    / \         / \
///   /   \       /   \
///  B(1)  C(1)  C(1)  D(2)
/// ~~~
/// 
/// Each node in the tree includes the element of the n-gram that it represents, and a count to represent that
/// the frequency of that element.
///
/// Some expectations about representing n-grams in this tree structure: 
/// - If a parent node has child nodes, the parent node count should match the sum of it's child node counts.
/// - The depth of the tree should match the size of the n-gram. For example: a bigram sholud have two
///   levels below the root, a trigram have three levels below the root.
/// 
/// Rather than implement the complexity of `TallyStoreType` directly, it is recommended to instead
/// implemenent the less complex `TallyStoreTreeNode` protocol. Doing so provides default implementation 
/// of `TallyStoreType` requirements. You will still need to create a lightweight `TallyStoreType` that
/// acts as a proxy for the root node.
///
/// See `MemoryTallyStore` for the most concise example of this appraoch.
public protocol TallyStoreTreeNode {
    
    associatedtype Item: Hashable
    
    /// An element of an n-gram.
    var element: NgramElement<Item> { get }
    
    /// The number of times the element occurs within this position in an ngram.
    /// When initalizing a new node, you should set the initial value to be 0.0.
    var count: Double { get set }
    
    /// Return a sequence of child nodes of this node.
    ///
    /// For implementations where it is expensive to get the children of a node in a single step,
    /// it's recommended to return a lazy sequence.
    var childNodes: AnySequence<Self> { get }
    
    /// Returns the child this node that represents the given element or nil if no such child exists.
    /// 
    /// - parameter element: The n-gram element used to identify which child node to return.
    /// - returns: The child node that represents an element, or nil if no child node exists.
    func findChildNode(with element: NgramElement<Item>) -> Self?

    /// Add a child node that represents an element.
    ///
    /// This method is only called with it's known that a child node representing this
    /// element does not exist, so to improve performance you should not perform this
    /// check in your own implementation.
    ///
    /// - parameter element: The n-gram element to represent with the child node.
    /// - returns: The newly created child node.
    func makeChildNode(with element: NgramElement<Item>) -> Self
    
}

extension TallyStoreTreeNode  {
    
    typealias ElementProbabilities = [(probability: Double, element: NgramElement<Item>)]
    
    mutating func incrementCount(for ngram: [NgramElement<Item>]) {
        
        let (_, tailElements) = ngram.headAndTail()
        
        if let element = tailElements.first {
            var child = findChildNode(with: element) ?? makeChildNode(with: element)
            child.incrementCount(for: tailElements)
        }
        else {
            count += 1
        }
    }
    
    func nextElement(following elements: [NgramElement<Item>]) -> ElementProbabilities {
        
        let (_, tailElements) = elements.headAndTail()
        
        if let element = tailElements.first {
            
            if let child = findChildNode(with: element) {
                return child.nextElement(following: tailElements)
            }
            else { return [] }
        }
            
        else { // tail is empty
            
            let total: Double = childNodes.reduce(0.0, { partial, child in
                return partial + child.count
            })
            
            return childNodes.map({ child in
                let prob = child.count / total
                return (probability: prob, element: child.element)
            })
        }
    }
    
    func distributions(excluding excludedElements: [NgramElement<Item>] = []) -> ElementProbabilities {
        
        let total: Double = childNodes.reduce(0.0, { partial, child in
            if child.element.isBoundaryOrRoot { return partial }
            if excludedElements.contains(child.element) { return partial }
            return partial + child.count
        })
        
        return childNodes.flatMap { child in
            
            if child.element.isBoundaryOrRoot { return nil }
            if excludedElements.contains(child.element) { return nil }
            
            let prob = child.count / total
            return (probability: prob, element: child.element)
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
    
    public typealias ElementProbabilities = [(probability: Double, element: NgramElement<Item>)]
    
    private let _incrementCount: ([NgramElement<Item>]) -> Void
    private let _incrementCountWithCompletion: ([NgramElement<Item>], (() -> Void)?) -> Void
    private let _nextElement: ([NgramElement<Item>]) -> ElementProbabilities
    private let _distributions: ([NgramElement<Item>]) -> ElementProbabilities
    
    public init<Store>(_ store: Store) where Store: TallyStoreType, Store.Item == Item {
        _incrementCount = store.incrementCount
        _nextElement = store.nextElement
        _distributions = store.distributions
        _incrementCountWithCompletion = store.incrementCount
    }
    
    public func incrementCount(for ngram: [NgramElement<Item>]) {
        _incrementCount(ngram)
    }
    
    public func incrementCount(for ngram: [NgramElement<Item>], completed closure: (() -> Void)? = nil) {
        _incrementCountWithCompletion(ngram, closure)
    }
    
    public func nextElement(following elements: [NgramElement<Item>]) -> ElementProbabilities {
        return _nextElement(elements)
    }
    
    public func distributions(excluding excludedElements: [NgramElement<Item>] = []) -> ElementProbabilities {
        return _distributions(excludedElements)
    }
}
