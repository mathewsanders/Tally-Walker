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
public enum TallySequenceType: Int {
    
    /// Represents sequences where there is no arbitary beginning or end of data, for example weather patterns.
    case continuousSequence
    
    /// Represents sequences where there the beginning and end of the sequence is meaningful, for example sentences.
    case discreteSequence
    
    /// Returns true if this model represents continuous sequences
    public var isContinuous: Bool {
        return self == .continuousSequence
    }
    
    /// Returns true if this model represents discrete sequences
    public var isDiscrete: Bool {
        return self == .discreteSequence
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
    
    /// Type used to identify an item
    public typealias Id = String
    
    /// An ItemProbability is a tuple combining an item, and it's probability.
    ///
    /// - probability is a `Double` between 0.0 and 1.0
    /// - item is a `Node` which may represent a literal item, or a sequence boundary
    public typealias ItemProbability = (probability: Double, item: Node<Item>)
    
    /// The type of n-gram to use when building the frequency model.
    public let ngram: NgramType
    
    /// The type of sequence that the frequency model represents.
    public let sequence: TallySequenceType
    
    /// An object responsible for maintaining the state of the model.
    /// If no object is supplied, the model will use an instance of `MemoryTallyStore`.
    public var store: AnyTallyStore<Item>?
    
    private var _memoryStore: AnyTallyStore<Item>
    
    private var _store: AnyTallyStore<Item> {
        return store ?? _memoryStore // use external store if it exists, fall back in in-memory store
    }
    
    internal var recentlyObserved: [Node<Item>]
    
    /// Initializes and returns a new tally object.
    ///
    /// - parameter sequenceType: The type of sequence this model represents (default value is `SequenceType.continuousSequence`).
    /// - parameter ngram: The type of n-gram to use when building the frequency model (default value is `Ngram.bigram`).
    ///
    /// - returns: An initialized frequency model object ready to start training.
    public init(representing sequenceType: TallySequenceType = .continuousSequence, ngram: NgramType = .bigram) {
        
        if ngram.size < 2 {
            NSException(name: NSExceptionName.invalidArgumentException, reason: "Model depth must be greater than 1", userInfo: nil).raise()
        }
        
        self.ngram = ngram
        self.sequence = sequenceType
        self._memoryStore = AnyTallyStore(MemoryTallyStore<Item>())
        self.recentlyObserved = []
    }
    
    /// Start a series of method calls to observe an item from a sequence.
    public mutating func startSequence(completed closure: (() -> Void)? = nil) {
        recentlyObserved.removeAll()
        observe(next: nodeForStart, completed: closure)
    }
    
    /// Conclude a series of method calls to observe an item from a sequence.
    public mutating func endSequence(completed: (() -> Void)? = nil) {
        observe(next: nodeForEnd, completed: completed)
        recentlyObserved.removeAll()
    }
    
    /// Observes the next item in a sequence as part of training the frequency model.
    ///
    /// - parameters:
    ///     - item: The item to observe.
    ///     - completed: A closure object containing behaviour to perform once observation is completed.
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
    public mutating func observe(next item: Item, completed closure: (() -> Void)? = nil) {
        observe(next: Node.item(item), completed: closure)
    }
    
    /// Observes a sequence of items.
    /// If the model is using a `TallyStoreType` that supports asynchronous observations the completed closure
    /// will be called when observations are completed.
    ///
    /// For TallyStoreTypes that do not support asynchronous observations, the completed closure will be called 
    /// immediately.
    ///
    /// - parameters:
    ///     - items: The sequence of items to observe.
    ///     - completed: A closure object containing behaviour to perform once observation is completed.
    ///
    /// This method does *not* need to be surrounded by calls to `startSequence()` and `endSequence()`.
    public mutating func observe(sequence items: [Item], completed: (() -> Void)? = nil) {
        
        if let completed = completed {
            let closureGroup = DispatchGroup()
            
            closureGroup.enter()
            startSequence {
                closureGroup.leave()
            }
            
            items.forEach{ item in
                closureGroup.enter()
                observe(next: item) {
                    closureGroup.leave()
                }
            }
            
            closureGroup.enter()
            endSequence{
                closureGroup.leave()
            }
            
            closureGroup.notify(queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.userInteractive)) {
                completed()
            }
        }
        else {
            startSequence()
            
            items.forEach{ item in
                observe(next: item)
            }
            endSequence()
        }
    }
    
    internal mutating func observe(next node: Node<Item>, completed: (() -> Void)? = nil) {
        
        recentlyObserved.append(node)
        recentlyObserved.clamp(to: ngram.size)
        
        if let completed = completed {
            let closureGroup = DispatchGroup()
            
            for itemIndex in 0..<recentlyObserved.count {
                let sequence = recentlyObserved.clamped(by: recentlyObserved.count - itemIndex)
                
                closureGroup.enter()
                _store.incrementCount(for: sequence) {
                    closureGroup.leave()
                }
            }
            
            closureGroup.notify(queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.userInteractive)) {
                completed()
            }
        }
        else {
            for itemIndex in 0..<recentlyObserved.count {
                let sequence = recentlyObserved.clamped(by: recentlyObserved.count - itemIndex)
                _store.incrementCount(for: sequence)
            }
        }
    }
    
    /// Get the overall relative frequencies of individual items in the model.
    ///
    /// - parameter excludedItems: An array of items to exclude from the calculation.
    ///
    /// - returns: An array of item probabilities which may be empty.
    public func distributions(excluding excludedItems: [Node<Item>] = []) -> [ItemProbability] {
        return _store.distributions(excluding: excludedItems)
    }
    
    /// Get the distribution of items that represent items that have started a sequence.
    ///
    /// For models representing continuous sequences, starting items are arbitary so the relative frequency of individual items is used instead.
    ///
    /// - returns: An array of item probabilities which may be empty.
    public func startingItems() -> [ItemProbability] {
        switch sequence {
        case .continuousSequence: return distributions()
        case .discreteSequence: return itemProbabilities(after: Node.sequenceStart)
        }
    }
    
    /// Get the probabilities of items that have observed to follow an individual item.
    ///
    /// - parameter item: The item used to check the frequency model.
    ///
    /// - returns: An array of item probabilities. If the model has no record of this item an empty array is returned.
    public func itemProbabilities(after item: Item) -> [ItemProbability] {
        return self.itemProbabilities(after: [item])
    }
    
    /// Get the probabilities of items that have observed to follow a sequence of items.
    ///
    /// - parameter sequence: The array of items used to check the frequency model. The length of this array should be less than the size of the n-gram used to build the frequency model.
    ///
    /// *Note:* If this array is larger, or the same size as the size of n-gram used to build this model, then this array will automatically be truncated to the largest size that the model can use.
    ///
    /// returns: An array of item probabilities. If the model has no record of this item an empty array is returned.
    public func itemProbabilities(after sequence: [Item]) -> [ItemProbability] {
        let items = sequence.map({ item in return Node.item(item) })
        return self.itemProbabilities(after: items)
    }
    
    public func itemProbabilities(after node: Node<Item>) -> [ItemProbability] {
        return self.itemProbabilities(after: [node])
    }
    
    public func itemProbabilities(after nodes: [Node<Item>]) -> [ItemProbability] {
        if ngram.size <= nodes.count {
            print("Tally.items(following:) Warning: attempting to match sequence of \(nodes.count) items, which exceeds the n-gram size of \(ngram.size). The sequence of items has been automatically clamped to \(ngram.size-1)")
        }
        let tail = nodes.clamped(by: ngram.size-1)
        return _store.itemProbabilities(after: tail)
    }
    
    internal var nodeForStart: Node<Item> {
        switch self.sequence {
        case .continuousSequence: return .unseenLeadingItems
        case .discreteSequence: return .sequenceStart
        }
    }
    
    internal var nodeForEnd: Node<Item> {
        switch self.sequence {
        case .continuousSequence: return .unseenTrailingItems
        case .discreteSequence: return .sequenceEnd
        }
    }
}

// MARK: -

/// Different types of nodes used to represent ngram.
///
/// Nodes may represent an actual item in a sequence, or a sequence boundary.
public enum Node<Item: Hashable>: Hashable {
    
    /// A literal item in the sequence.
    case item(Item)
    
    /// Represents unseen items that come before the observed segment of a continuous sequence.
    case unseenLeadingItems
    
    /// Represents unseen items that come after the observed segment of a continuous sequence.
    case unseenTrailingItems
    
    /// Represents the start of a discrete sequence.
    case sequenceStart
    
    /// Represents the end of a discrete sequence.
    case sequenceEnd
    
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
        case .unseenLeadingItems, .unseenTrailingItems, .sequenceEnd, .sequenceStart, .root: return true
        }
    }
    
    internal var isObservableBoundary: Bool {
        switch self {
        case .item, .sequenceEnd, .sequenceStart, .root: return false
        case .unseenLeadingItems, .unseenTrailingItems: return true
        }
    }
    
    public var hashValue: Int {
        switch self {
        case .root: return 0
        case .sequenceStart: return 1
        case .sequenceEnd: return 2
        case .unseenLeadingItems: return 3
        case .unseenTrailingItems: return 4
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
        case (.sequenceStart, .sequenceStart): return true
        case (.sequenceEnd, .sequenceEnd): return true
        case(.unseenLeadingItems, .unseenLeadingItems): return true
        case(.unseenTrailingItems, .unseenTrailingItems): return true
        case let(.item(leftItem), item(rightItem)): return leftItem == rightItem
        default: return false
        }
    }
}

extension Array where Iterator.Element: Hashable {
    mutating func clamp(to size: Int) {
        self = Array(self.suffix(size))
    }
    
    func clamped(by size: Int) -> [Element] {
        return Array(self.suffix(size))
    }
    
    func headAndTail() -> (Element, [Element]) {
        
        if self.isEmpty {
            NSException(name: NSExceptionName.invalidArgumentException, reason: "Array can not be empty", userInfo: nil).raise()
        }
        
        var tail = self
        let head = tail.remove(at: 0)
        
        return (head, tail)
    }
}
