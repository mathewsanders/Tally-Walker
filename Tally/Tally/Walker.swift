// Walker.swift
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

/// Options that describe the number of steps to look at when considering the next step in  a random walk.
public enum WalkType<Item: Hashable> {
    
    /// Use a 1-st order markov chain, which only looks at the last step taken.
    case markovChain
    
    /// Look at the longest number of steps possible for an associated frequency model.
    case matchModel
    
    /// Attempt to look at a specific number of steps. This should be used to look at a shorter number of steps than allowed in the frequency model.
    case steps(Int)
    
    /// The number of steps to look at when considering the next step in a random walk.
    func numberOfSteps(for model: Tally<Item>) -> Int {
        switch self {
        case .markovChain: return 1
        case .matchModel: return model.ngram.size - 1
        case .steps(let steps): return steps
        }
    }
}

/// A Walker object generates sequences of items based of n-grams of items from a Tally object.
public struct Walker<Item: Hashable> : Sequence, IteratorProtocol {
    
    private let frequencyModel: Tally<Item>
    private let walk: WalkType<Item>
    
    internal typealias ItemProbability = (item: Node<Item>, probability: Double)
    
    internal var newSequence = true
    internal var lastSteps: [Item] = []
    
    /// Initializes and returns a new walker object.
    ///
    /// - parameter model: The frequency model to use for random walks.
    /// - parameter walk: Option for the number of steps to look at when making the next step in a random walk (default value is `WalkType.matchModel`).
    ///
    /// - returns: An initialized walker object ready to start generating new sequences.
    public init(model: Tally<Item>, walkOptions walk: WalkType<Item> = .matchModel) {
        self.frequencyModel = model
        self.walk = walk
        
        // seed random number generator
        let time = Int(NSDate.timeIntervalSinceReferenceDate)
        srand48(time)
    }
    
    /// Fills a array with sequence of items.
    ///
    /// - parameter request: The number of items make the sequence.
    /// For models of discrete sequences the actual number of items may be less than requested.
    /// For models of continuous sequences the number of items should always match the requested number.
    ///
    /// - returns: An array of items generated from a random walk on the `Tally` frequency model.
    public mutating func fill(request: Int) -> [Item] {
        if frequencyModel.sequence.isDiscrete { endWalk() }
        return Array(self.prefix(request))
    }
    
    /// End the current walk so that the next call to `next()` starts a new random walk.
    public mutating func endWalk() {
        newSequence = true
        lastSteps.removeAll()
    }
    
    mutating public func next() -> Item? {
        return nextStep()
    }
    
    /// Returns the next item in a random walk of the model.
    ///
    /// How the next item to return is chosen depends on changes depending on the underlying model.
    ///
    /// If the model is empty, nil will always be returned
    ///
    /// For models representing continuous sequences:
    /// - the first item returned will be picked based on the distribution of all items
    /// - subsequent items will be based on a random walk considering the last n items picked
    /// - nil will never be returned, unless the model is empty
    ///
    /// For models representing discrete sequences:
    /// - the first item returned will be picked based on the distribution of all starting items
    /// - subsequent items will be based on a random walk considering the last n items picked
    /// - nil will be returned to represent the end of the sequence
    ///
    /// - returns: the next item, if it exists, or nil if the end of the sequence has been reached
    mutating public func nextStep() -> Item? {
        
        // empty model
        if frequencyModel.startingItems().isEmpty {
            print("Walker.next() Warning: attempting to generate an item from empty model")
            return nil
        }
        
        // starting a new sequence
        if newSequence {
            
            newSequence = false
            lastSteps.removeAll()
            let step = randomWalk(from: frequencyModel.startingItems())
            if let item = step.item {
                lastSteps = [item]
            }
            return step.item
        }
            
            // continuing an existing sequence
        else {
            
            lastSteps.clamp(to: walk.numberOfSteps(for: frequencyModel))
            
            // continuing a discrete sequence (okay to return nil)
            if frequencyModel.sequence.isDiscrete {
                let nextSteps = frequencyModel.items(following: lastSteps)
                let step = randomWalk(from: nextSteps)
                if let item = step.item {
                    lastSteps.append(item)
                }
                return step.item
            }
                
                // continuing a continuous sequence (always want to return next item)
            else if frequencyModel.sequence.isContinuous {
                
                var foundStep = false
                var item: Item? = nil
                
                while !foundStep {
                    
                    if lastSteps.isEmpty {
                        let step = randomWalk(from: frequencyModel.startingItems())
                        item = step.item
                        foundStep = true
                    }
                    else {
                        let nextSteps = frequencyModel.items(following: lastSteps)
                        let step = randomWalk(from: nextSteps)
                        
                        if let _ = step.item {
                            item = step.item
                            foundStep = true
                        }
                        else if step.isObservableBoundary {
                            
                            var nextSteps = frequencyModel.distributions(excluding: nextSteps.map({ $0.item }))
                            if nextSteps.isEmpty {
                                nextSteps = frequencyModel.distributions()
                            }
                            let step = randomWalk(from: nextSteps)
                            if let _ = step.item {
                                item = step.item
                                foundStep = true
                            }
                        }
                        if !foundStep {
                            lastSteps.remove(at: 0)
                        }
                    }
                }
                if let item = item {
                    lastSteps.append(item)
                }
                return item
            }
        }
        return nil
    }
    
    internal mutating func randomWalk(from possibleSteps: [ItemProbability]) -> Node<Item> {
        
        if possibleSteps.isEmpty {
            NSException(name: NSExceptionName.invalidArgumentException, reason: "Walker.randomWalk can not choose from zero possibilities", userInfo: nil).raise()
        }
        if possibleSteps.count == 1 { return possibleSteps[0].item }
        
        var base = 1.0
        
        typealias StepLimit = (item: Node<Item>, limit: Double)
        
        // translate probabilities into lower limits
        // e.g. (0.25, 0.5, 0.25) -> (0.75, 0.25, 0.0)
        let lowerLimits: [StepLimit] = possibleSteps.map { possibleStep in
            let limit = base - possibleStep.probability
            base = limit
            return (item: possibleStep.item, limit: limit)
        }
        
        // returns a double 0.0..<1.0
        let randomLimit = drand48()
        
        // choose the step based on a randomly chosen limit
        let step = lowerLimits.first { _, lowerLimit in
            return lowerLimit < randomLimit
        }
        
        return step!.item
    }
}
