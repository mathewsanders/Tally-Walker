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
/// 
/// - `continuousSequence`: Represents sequences where there is no arbitary beginning or end of data,
///   for example weather patterns.
/// - `discreteSequence`: Represents sequences where there the beginning and end of the sequence is 
///   meaningful, for example sentences.
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

/// Options for the size of an n-gram.
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

/// A Tally is an interface to building a frequency model of n-grams from observed sequences.
///
/// Can be used with any item that adopts the `Hashable` protocol.
public struct Tally<Item: Hashable> {
    
    /// Type used to identify an item
    public typealias Id = String
    
    /// An array of tuples representing an element, and the probability of the element occuring next in a sequence.
    ///
    /// - probability is a `Double` between 0.0 and 1.0.
    /// - element may be a literal item, or a sequence boundary.
    ///
    /// The array may be empty.
    /// If the array is not empty, the sum of probabilities should approach 1.0.
    public typealias ElementProbabilities = [(probability: Double, element: NgramElement<Item>)]
    
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
    
    /// A closure used to transform any item before it is observed by the model, or when querying the model
    /// about an item.
    ///
    /// If an Item also adopts the `TallyNormalizer` protocol, and this closure is also defined, then the
    /// value returned by this closure is used instead of the result returned by the `TallyNormalizer` 
    /// `normalized()` method.
    public var normalizer: ( (Item) -> Item )? = nil
    
    private var recentlyObserved: [NgramElement<Item>]
    
    /// Initializes and returns a new Tally object.
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
        observe(next: elementForStart, completed: closure)
    }
    
    /// Conclude a series of method calls to observe an item from a sequence.
    public mutating func endSequence(completed: (() -> Void)? = nil) {
        observe(next: elementForEnd, completed: completed)
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
        observe(next: NgramElement.item(normalize(item)), completed: closure)
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
                observe(next: normalize(item)) {
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
                observe(next: normalize(item))
            }
            endSequence()
        }
    }
    
    private mutating func observe(next element: NgramElement<Item>, completed: (() -> Void)? = nil) {
        
        recentlyObserved.append(element)
        recentlyObserved.clamp(to: ngram.size)
        
        if let completed = completed {
            let closureGroup = DispatchGroup()
            
            for itemIndex in 0..<recentlyObserved.count {
                let ngram = recentlyObserved.clamped(by: recentlyObserved.count - itemIndex)
                
                closureGroup.enter()
                _store.incrementCount(for: ngram) {
                    closureGroup.leave()
                }
            }
            
            closureGroup.notify(queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.userInteractive)) {
                completed()
            }
        }
        else {
            for itemIndex in 0..<recentlyObserved.count {
                let ngram = recentlyObserved.clamped(by: recentlyObserved.count - itemIndex)
                _store.incrementCount(for: ngram)
            }
        }
    }
    
    /// Get the overall relative frequencies of individual elements in the model.
    ///
    /// - parameter excludedElements: An array of elements to exclude from frequencies.
    ///
    /// - returns: An array of element probabilities.
    public func distributions(excluding excludedElements: [NgramElement<Item>] = []) -> ElementProbabilities {
        return _store.distributions(excluding: excludedElements)
    }
    
    /// Get the distribution of elements that have started a sequence.
    ///
    /// For models representing continuous sequences, starting elements are arbitary so the relative
    /// frequency of individual elements is used instead.
    ///
    /// - returns: Probabilities of elements starting a sequence.
    public func startingElements() -> ElementProbabilities {
        switch sequence {
        case .continuousSequence: return distributions()
        case .discreteSequence: return elementProbabilities(after: NgramElement.sequenceStart)
        }
    }
    
    /// Get the probabilities of elements expected to occur after an individual item.
    ///
    /// - parameter item: The item used to check the frequency model.
    ///
    /// - returns: Probabilities of an element occuring after the given item. This may return an empty array.
    public func elementProbabilities(after item: Item) -> ElementProbabilities {
        return self.elementProbabilities(following: [normalize(item)])
    }
    
    /// Get the probabilities of elements that have observed to follow a sequence of items.
    ///
    /// - parameter sequence: The array of items used to check the frequency model. The length of this array should be less than the size of the n-grams used to build the model.
    ///
    /// *Note:* If this array is larger, or the same size as the size of n-gram used to build this model, then this array will automatically be truncated to the largest size that the model can use.
    ///
    /// returns: Probabilities of an element occuring after the given item. This may return an empty array.
    public func elementProbabilities(following sequence: [Item]) -> ElementProbabilities {
        let elements = sequence.map({ item in return NgramElement.item(normalize(item)) })
        return self.elementProbabilities(following: elements)
    }
    
    private func elementProbabilities(after element: NgramElement<Item>) -> ElementProbabilities {
        return self.elementProbabilities(following: [element])
    }
    
    private func elementProbabilities(following elements: [NgramElement<Item>]) -> ElementProbabilities {
        if ngram.size <= elements.count {
            print("Tally.items(following:) Warning: attempting to match sequence of \(elements.count) items, which exceeds the n-gram size of \(ngram.size). The sequence of items has been automatically clamped to \(ngram.size-1)")
        }
        let tail = elements.clamped(by: ngram.size-1)
        return _store.nextElement(following: tail)
    }
    
    private var elementForStart: NgramElement<Item> {
        switch self.sequence {
        case .continuousSequence: return .unseenLeadingItems
        case .discreteSequence: return .sequenceStart
        }
    }
    
    private var elementForEnd: NgramElement<Item> {
        switch self.sequence {
        case .continuousSequence: return .unseenTrailingItems
        case .discreteSequence: return .sequenceEnd
        }
    }
    
    private func normalize(_ item: Item) -> Item {
        
        if let normalizer = normalizer {
            return normalizer(item)
        }
        
        if let normalizable = item as? TallyNormalizer, let normalizedItem = normalizable.normalized() as? Item {
            return normalizedItem
        }
        return item
    }
}

// MARK: -

/// Types that implement this protocol will use the value returned from the `normalized()`
/// method when updating or reviewing a Tally model.
public protocol TallyNormalizer {
    
    /// The alternate value to use when updating or reviewing a Tally model.
    ///
    /// If the Tally model's `normalized` closure is defined, then the resulf of 
    /// that closure will be used instead of the result of this method.
    func normalized() -> Self
}

// MARK: -
// see: https://github.com/apple/swift/blob/master/docs/GenericsManifesto.md#nested-generics


/// An element within an ngram.
///
/// An element may represent an item observed from a sequence, or represent a sequence boundary.
public enum NgramElement<Item: Hashable>: Hashable {
    
    /// A literal item.
    case item(Item)
    
    /// Represents unseen items that come before the observed segment of a continuous sequence.
    case unseenLeadingItems
    
    /// Represents unseen items that come after the observed segment of a continuous sequence.
    case unseenTrailingItems
    
    /// Represents the start of a discrete sequence.
    case sequenceStart
    
    /// Represents the end of a discrete sequence.
    case sequenceEnd
    
    /// The item this node represents, or nil if the node represents a sequence boundary.
    public var item: Item? {
        switch self {
        case .item(let item): return item
        default: return nil
        }
    }
    
    internal var isBoundary: Bool {
        switch self {
        case .item: return false
        case .unseenLeadingItems, .unseenTrailingItems, .sequenceEnd, .sequenceStart: return true
        }
    }
    
    internal var isObservableBoundary: Bool {
        switch self {
        case .item, .sequenceEnd, .sequenceStart: return false
        case .unseenLeadingItems, .unseenTrailingItems: return true
        }
    }
    
    public var hashValue: Int {
        switch self {
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
    public static func ==(lhs: NgramElement<Item>, rhs: NgramElement<Item>) -> Bool {
        switch (lhs, rhs) {
        case (.sequenceStart, .sequenceStart): return true
        case (.sequenceEnd, .sequenceEnd): return true
        case(.unseenLeadingItems, .unseenLeadingItems): return true
        case(.unseenTrailingItems, .unseenTrailingItems): return true
        case let(.item(leftItem), item(rightItem)): return leftItem == rightItem
        default: return false
        }
    }
}

// MARK: -

extension Array where Iterator.Element: Hashable {
    mutating func clamp(to size: Int) {
        self = Array(self.suffix(size))
    }
    
    func clamped(by size: Int) -> [Element] {
        return Array(self.suffix(size))
    }
    
    func headAndTail() -> (Element, [Element]) {
        
        if self.isEmpty {
            NSException(name: NSExceptionName.invalidArgumentException, reason: "Array must have at least one element to get head and tail", userInfo: nil).raise()
        }
        
        var tail = self
        let head = tail.remove(at: 0)
        
        return (head, tail)
    }
}
