//
//  CoreDataTallyStore.swift
//  Tally
//
//  Created by mat on 11/15/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import Foundation
import CoreData

// http://redqueencoder.com/property-lists-and-user-defaults-in-swift/
/// A representation of a Type with internal property keys and values mapped to a NSDictionary that can be used in store
protocol TallyStoreType: Hashable {
    init?(dictionaryRepresentation:NSDictionary?)
    func dictionaryRepresentation() -> NSDictionary
}

class TallyCoreDataStore<StoreItem: TallyStoreType>: TallyStoreDelegate {
    
    typealias Item = StoreItem
    
    var stack = CoreDataStack()
    
    public typealias Root = CoreDataNode
    public var root: Root
    
    var context: NSManagedObjectContext {
        return stack.persistentContainer.viewContext
    }
    
    init() {
        //self.root = NodeEdges(withItem: .root)
        self.root = CoreDataNode(context: stack.persistentContainer.viewContext)
    }
    
    deinit {
        stack.saveContext()
    }
    
    public func incrementCount(for sequence: [Node<Item>]) {
        root.incrementCount(for: sequence)
    }
    
    public func itemProbabilities(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        return root.itemProbabilities(after: sequence)
    }
    
    func distributions(excluding excludedItems: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        
        let total: Double = root.children.reduce(0.0, { partial, child in
            
            let node = Node<Item>(dictionaryRepresentation: child.nodeDictionaryRepresentation)!
            
            if node.isBoundaryOrRoot { return partial }
            if excludedItems.contains(node) { return partial }
            return partial + child.count
        })
        
        return root.children.flatMap { child in
            
            let node = Node<Item>(dictionaryRepresentation: child.nodeDictionaryRepresentation)!
            
            if node.isBoundaryOrRoot { return nil }
            if excludedItems.contains(node) { return nil }
            
            let prob = child.count / total
            return (item: node, probability: prob)
        }
    }
}

extension Node where Item: TallyStoreType {
    
    init?(dictionaryRepresentation: NSDictionary) {
        print("creating node from dictionary")
        return nil // TODO: Implement
    }
    
    func dictionaryRepresentation() -> NSDictionary {
        print("creating dictionary from node")
        return NSDictionary() // TODO: Implement
    }
}

extension CoreDataNode {
    
    convenience init<Item: TallyStoreType>(node: Node<Item> = Node<Item>.root, in context: NSManagedObjectContext) {
        
        self.init(context: context)
        self.nodeDictionaryRepresentation = node.dictionaryRepresentation()
        
        // TODO: Check to see if constructor is ever called with non-empty collection of children
        self.count = 0.0
        self.children = []
    }
    
    func incrementCount<Item: TallyStoreType>(for sequence: [Node<Item>]) {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first, let context = managedObjectContext {
            
            let child = children.first(where: { node in
                return node.nodeDictionaryRepresentation == item.dictionaryRepresentation()
            }) ?? CoreDataNode(node: item, in: context)
            
            child.incrementCount(for: tail)
            child.parent = self
            //child.incrementCount(for: tail)
            //children[item] = child
        }
        else {
            count += 1
        }
    }
    
    func itemProbabilities<Item: TallyStoreType>(after sequence: [Node<Item>]) -> [(probability: Double, item: Node<Item>)] {
        
        let (_, tail) = sequence.headAndTail()
        
        if let item = tail.first {
            if let child = children.first(where: { node in
                return node.nodeDictionaryRepresentation == item.dictionaryRepresentation()
            }){
                return child.itemProbabilities(after: tail)
            }
        }
        else { // tail is empty
            let total: Double = children.reduce(0.0, { partial, child in
                return partial + child.count
            })
            
            return children.flatMap({ child in
                let prob = child.count / total
                if let item = Node<Item>(dictionaryRepresentation: child.nodeDictionaryRepresentation) {
                    return (probability: prob, item: item)
                }
                return nil // TODO: Better way to deal with unlikely failure than return nil?
            })
        }
        return []
    }
}


