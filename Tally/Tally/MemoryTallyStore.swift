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

/// A simple Tally store that uses a Dictionary to create an in-memory store of a Tally model.
/// This store is intended for transient Tally models.
public class MemoryTallyStore<Item>: TallyStoreType where Item: Hashable {
    
    private var root: MemoryNode<Item>
    
    public init() {
        self.root = MemoryNode()
    }
    
    // MARK: TallyStoreType
    
    public func incrementCount(for ngram: [NgramElement<Item>]) {
        root.incrementCount(for: ngram)
    }
    
    public func nextElement(following elements: [NgramElement<Item>]) -> [(probability: Double, element: NgramElement<Item>)] {
        return root.nextElement(following: elements)
    }
    
    public func distributions(excluding excludedElements: [NgramElement<Item>] = []) -> [(probability: Double, element: NgramElement<Item>)] {
        return root.distributions(excluding: excludedElements)
    }
}   

// MARK: - TallyStoreNodeType

fileprivate final class MemoryNode<Item>: TallyStoreTreeNode where Item: Hashable {
    
    typealias Children = [NgramElement<Item>: MemoryNode<Item>]
    
    let element: NgramElement<Item>!
    var count: Double = 0
    var children: Children = [:]
    
    init() {
        self.element = nil // root node
    }
    
    required init(withElement element: NgramElement<Item>) {
        self.element = element
    }
    
    var childNodes: AnySequence<MemoryNode<Item>>{
        return AnySequence(children.values)
    }
    
    func findChildNode(with element: NgramElement<Item>) -> MemoryNode<Item>? {
        return children[element]
    }
    
    func makeChildNode(with element: NgramElement<Item>) -> MemoryNode<Item> {
        let child = MemoryNode<Item>(withElement: element)
        children[element] = child
        return child
    }
}
