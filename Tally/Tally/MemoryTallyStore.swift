// MemoryTallyStore.swift
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

/// A simple Tally store that uses a Dictionary represent the state of a Tally model.
public class MemoryTallyStore<Item>: TallyStoreType where Item: Hashable {
    
    private var root: MemoryNode<Item>
    
    public init() {
        self.root = MemoryNode(withItem: .root)
    }
    
    // MARK: TallyStoreType
    
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

// MARK: - TallyStoreNodeType

fileprivate final class MemoryNode<Item>: TallyStoreNodeType where Item: Hashable {
    
    internal typealias Children = [Node<Item>: MemoryNode<Item>]
    
    internal let node: Node<Item>
    internal var count: Double = 0
    internal var children: Children = [:]
    
    required init(withItem node: Node<Item> = .root) {
        self.node = node
    }
    
    public var childNodes: AnySequence<MemoryNode<Item>>{
        return AnySequence(children.values)
    }
    
    public func findChildNode(with item: Node<Item>) -> MemoryNode<Item>? {
        return children[item]
    }
    
    public func makeChildNode(with item: Node<Item>) -> MemoryNode<Item> {
        let child = MemoryNode<Item>(withItem: item)
        children[child.node] = child
        return child
    }
}
