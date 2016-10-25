// Tally.swift
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

/// Options for the type of sequence that can be represented.
public enum SequenceType<Item: Hashable> {
    
    /// Represents sequences where there is no arbitary beginning or end of data, for example weather patterns.
    case continuousSequence
    
    /// Represents sequences where there the beginning and end of the sequence is meaningful, for example sentences.
    case discreteSequence
    
    /// Returns true if this model represents continuous sequences
    var isContinuous: Bool {
        return self == .continuousSequence
    }
    
    /// Returns true if this model represents discrete sequences
    var isDiscrete: Bool {
        return self == .discreteSequence
    }
    
    fileprivate var nodeForStart: Node<Item> {
        switch self {
        case .continuousSequence: return Node.observableBoundary
        case .discreteSequence: return Node.startBoundary
        }
    }
    
    fileprivate var nodeForEnd: Node<Item> {
        switch self {
        case .continuousSequence: return Node.observableBoundary
        case .discreteSequence: return Node.endBoundary
        }
    }
}

// MARK: -

/// Options for different types of n-grams.
public enum NgramType {
    
    /// An n-gram of two consequitive items
    case bigram
    
    /// An n-gram of two consequitive items
    case digram
    
    /// An n-gram of three consequitive items
    case trigram
    
    /// An n-gram of an arbitary depth
    /// - warning: attempting to create a `Tally` model with an n-gram size less than 2 will cause an error.
    /// - note: large ngram sizes will decrease performance and probably not increase the quality of predictions.
    case ngram(depth: Int)
    
    /// The number of items that this type of n-gram can hold
    public var size: Int {
        switch self {
        case .bigram, .digram: return 2
        case .trigram: return 3
        case .ngram(depth: let depth): return depth
        }
    }
}

// MARK: -

/// Use Tally to build a frequency model of items of n-grams based from observed sequences.
///
/// Can be used with any items that adopt the `Hashable` protocol.
public struct Tally<Item: Hashable> {
    
    /// An ItemProbability is a tuple combining an item, and it's probability.
    ///
    /// - item is a `Node` which may represent a literal item, or a sequence boundary.
    /// - probability is a `Double` between 0.0 and 1.0
    public typealias ItemProbability = (item: Node<Item>, probability: Double)
    
    /// The type of n-gram to use when building the frequency model.
    public let ngram: NgramType
    
    /// The type of sequence that the frequency model represents.
    public let sequence: SequenceType<Item>
    
    internal typealias Root = NodeEdges<Item>
    internal var root: Root
    internal var recentlyObserved: [Node<Item>]
    
    /// Initializes and returns a new tally object.
    ///
    /// - parameter sequenceType: The type of sequence this model represents (default value is `SequenceType.continuousSequence`).
    /// - parameter ngram: The type of n-gram to use when building the frequency model (default value is `Ngram.bigram`).
    ///
    /// - returns: An initialized frequency model object ready to start training.
    public init(representing sequenceType: SequenceType<Item> = .continuousSequence, ngram: NgramType = .bigram) {
        
        if ngram.size < 2 {
            NSException(name: NSExceptionName.invalidArgumentException, reason: "Model depth must be greater than 1", userInfo: nil).raise()
        }
        
        self.ngram = ngram
        self.sequence = sequenceType
        self.root = NodeEdges(withItem: .root)
        self.recentlyObserved = []
    }
    
    /// Start a series of method calls to observe an item from a sequence.
    public mutating func startSequence() {
        recentlyObserved.removeAll()
        observe(next: sequence.nodeForStart)
    }
    
    /// Conclude a series of method calls to observe an item from a sequence.
    public mutating func endSequence() {
        observe(next: sequence.nodeForEnd)
        recentlyObserved.removeAll()
    }
    
    /// Observes the next item in a sequence as part of training the frequency model.
    ///
    /// - parameter item: The item to observe.
    ///
    /// Call this method multiple times surrounded by calls to `startSequence()` and `endSequence()`.
    ///
    /// ~~~~
    /// // start a new sequence
    /// model.startSequence()
    ///
    /// // call multiple times as needed
    /// model.observe(next item: Item)
    ///
    /// // end the sequence
    /// model.endSequence()
    /// ~~~~
    public mutating func observe(next item: Item) {
        observe(next: Node.item(item))
    }
    
    /// Observes a sequence of items.
    ///
    /// - parameter items: The sequence of items to observe.
    ///
    /// This method does *not* need to be surrounded by calls to `startSequence()` and `endSequence()`.
    public mutating func observe(sequence items: [Item]) {
        startSequence()
        items.forEach{ item in
            observe(next: item)
        }
        endSequence()
    }
    
    internal mutating func observe(next node: Node<Item>) {
        
        recentlyObserved.append(node)
        recentlyObserved.clamp(to: ngram.size)
        
        for itemIndex in 0..<recentlyObserved.count {
            root.incrementCount(for: [root.node] + recentlyObserved.clamped(by: recentlyObserved.count - itemIndex))
        }
    }
    
    /// Get the overall relative frequencies of individual items in the model.
    ///
    /// - parameter excludedItems: An array of items to exclude from the calculation.
    ///
    /// - returns: An array of item probabilities which may be empty.
    public func distributions(excluding excludedItems: [Node<Item>] = []) -> [ItemProbability] {
        
        let total: Int = root.children.values.reduce(0, { partial, edge in
            if edge.node.isBoundaryOrRoot { return partial }
            if excludedItems.contains(edge.node) { return partial }
            return partial + edge.count
        })
        
        return root.children.values.flatMap { edge in
            
            if edge.node.isBoundaryOrRoot { return nil }
            if excludedItems.contains(edge.node) { return nil }
            
            let prob = Double(edge.count) / Double(total)
            return (item: edge.node, probability: prob)
        }
    }
    
    /// Get the distribution of items that represent items that have started a sequence.
    ///
    /// For models representing continuous sequences, starting items are arbitary so the relative frequency of individual items is used instead.
    ///
    /// - returns: An array of item probabilities which may be empty.
    public func startingItems() -> [ItemProbability] {
        switch sequence {
        case .continuousSequence: return distributions()
        case .discreteSequence: return self.items(following: Node.startBoundary)
        }
    }
    
    /// Get the probabilities of items that have observed to follow an individual item.
    ///
    /// - parameter item: The item used to check the frequency model.
    ///
    /// - returns: An array of item probabilities. If the model has no record of this item an empty array is returned.
    public func items(following item: Item) -> [ItemProbability] {
        return self.items(following: [item])
    }
    
    /// Get the probabilities of items that have observed to follow a sequence of items.
    ///
    /// - parameter sequence: The array of items used to check the frequency model. The length of this array should be less than the size of the n-gram used to build the frequency model.
    ///
    /// *Note:* If this array is larger, or the same size as the size of n-gram used to build this model, then this array will automatically be truncated to the largest size that the model can use.
    ///
    /// returns: An array of item probabilities. If the model has no record of this item an empty array is returned.
    public func items(following sequence: [Item]) -> [ItemProbability] {
        let items = sequence.map({ item in return Node.item(item) })
        return self.items(following: items)
    }
    
    public func items(following node: Node<Item>) -> [ItemProbability] {
        return self.items(following: [node])
    }
    
    public func items(following nodes: [Node<Item>]) -> [ItemProbability] {
        if ngram.size <= nodes.count {
            print("Tally.items(following:) Warning: attempting to match sequence of \(nodes.count) items, which exceeds the n-gram size of \(ngram.size). The sequence of items has been automatically clamped to \(ngram.size-1)")
        }
        let tail = nodes.clamped(by: ngram.size-1)
        return root.itemProbabilities(following: [root.node]+tail)
    }
}

// MARK: -

/// Different types of nodes used to build a tree of `NodeEdges`.
///
/// Nodes may represent an actual item in a sequence, or a sequence boundary.
public enum Node<Item: Hashable>: Hashable {
    
    /// A literal item in the sequence.
    case item(Item)
    
    /// Represents the either the start or end boundary of an observed sample of a continuous sequence.
    case observableBoundary
    
    /// Represents the start of a discrete sequence.
    case startBoundary
    
    /// Represents the end of a discrete sequence.
    case endBoundary
    
    /// The root node
    case root
    
    /// The item this node represents, or nil if the node represents a sequence boundary.
    public var item: Item? {
        switch self {
        case .item(let item): return item
        default: return nil
        }
    }
    
    internal var isBoundaryOrRoot: Bool {
        switch self {
        case .item: return false
        case .observableBoundary, .endBoundary, .startBoundary, .root: return true
        }
    }
    
    internal var isObservableBoundary: Bool {
        switch self {
        case .item, .endBoundary, .startBoundary, .root: return false
        case .observableBoundary: return true
        }
    }
    
    public var hashValue: Int {
        switch self {
        case .root: return 0
        case .startBoundary: return 1
        case .endBoundary: return 2
        case .observableBoundary: return 3
        case .item(let item): return item.hashValue
        }
    }
    
    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func ==(lhs: Node<Item>, rhs: Node<Item>) -> Bool {
        switch (lhs, rhs) {
        case (.root, .root): return true
        case (.startBoundary, .startBoundary): return true
        case (.endBoundary, .endBoundary): return true
        case(.observableBoundary, .observableBoundary): return true
        case let(.item(leftItem), item(rightItem)): return leftItem == rightItem
        default: return false
        }
    }
}

// MARK: -

internal struct NodeEdges<Item: Hashable> {
    
    internal typealias Nodes = [Node<Item>]
    internal typealias Children = [Node<Item>: NodeEdges<Item>]
    internal typealias ItemProbability = (item: Node<Item>, probability: Double)
    
    internal let node: Node<Item>
    internal var count: Int = 0
    internal var children: Children = [:]
    
    init(withItem node: Node<Item> = .root) {
        self.node = node
    }
    
    mutating func incrementCount(for sequence: Nodes) {
        
        let (_, tail) = headAndTail(from: sequence)
        
        if let item = tail.first {
            var child = children[item] ?? NodeEdges<Item>(withItem: item)
            child.incrementCount(for: tail)
            children[item] = child
        }
        else {
            count += 1
        }
    }
    
    func itemProbabilities(following sequence: Nodes) -> [ItemProbability] {
        
        let (_, tail) = headAndTail(from: sequence)
        
        if let item = tail.first {
            if let child = children[item] {
                return child.itemProbabilities(following: tail)
            }
        }
        else { // tail is empty
            let total: Int = children.values.reduce(0, { partial, sequence in
                return partial + sequence.count
            })
            
            return children.values.map({ child in
                let prob = Double(child.count) / Double(total)
                return (item: child.node, probability: prob)
            })
        }
        return []
    }
    
    internal func headAndTail(from items: Nodes) -> (Node<Item>, Nodes) {
        
        if items.isEmpty {
            NSException(name: NSExceptionName.invalidArgumentException, reason: "Items can not be empty", userInfo: nil).raise()
        }
        
        var itemsTail = items
        let itemsHead = itemsTail.remove(at: 0)
        
        if self.node != itemsHead {
            NSException(name: NSExceptionName.invalidArgumentException, reason: "First item \(itemsHead) does not match item \(self.node)", userInfo: nil).raise()
        }
        
        return (itemsHead, itemsTail)
    }
}

extension Array where Iterator.Element: Hashable {
    mutating func clamp(to size: Int) {
        self = Array(self.suffix(size))
    }
    
    func clamped(by size: Int) -> [Element] {
        return Array(self.suffix(size))
    }
}
