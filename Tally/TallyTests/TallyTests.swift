//
//  TallyTests.swift
//  TallyTests
//
//  Created by Mathew Sanders on 10/24/16.
//  Copyright © 2016 Mat. All rights reserved.
//

import XCTest
@testable import Tally

class TallyTests: XCTestCase {
    
    typealias Weather = Character
    let equalSunnyRainyDays: [Weather] = ["🌧","🌧","🌧","🌧", "☀️","☀️","☀️","☀️"]
    var continuousModel: Tally<Weather>!
    var continuousWalker: Walker<Weather>!
    
    override func setUp() {
        super.setUp()
        
        continuousModel = Tally<Weather>()
        continuousModel.observe(sequence: equalSunnyRainyDays)
        continuousWalker = Walker(model: continuousModel)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testDefaultModelSettings() {
        
        // check the default settings used to create a model
        XCTAssertTrue(continuousModel.ngram.size == NgramType.bigram.size, "Default n-gram should be bigram")
        XCTAssertTrue(continuousModel.sequence.isContinuous, "Default Tally should be continuous")
    }
    
    func testDistributions() {
        
        // check there are two items, and both have probability of 0.5
        let distributions = continuousModel.distributions()
        
        XCTAssertTrue(distributions.count == 2, "Unexpected number of distributions")
        XCTAssertTrue(distributions[0].probability == 0.5, "Probability should be 0.5")
        XCTAssertTrue(distributions[1].probability == 0.5, "Probability should be 0.5")
    }
    
    func testWalkerFill() {
        
        let fillSize = 10
        var sunnyDays: [Int] = []
        var rainyDays: [Int] = []
        
        for _ in 0..<1000 {
            
            // fill for continuous sequence should always return the requested size
            let sequence = continuousWalker.fill(request: fillSize)
            XCTAssertTrue(sequence.count == fillSize, "Fill should have generated \(fillSize) items")
            
            sunnyDays.append(numberOfDays(in: sequence, matching: "☀️"))
            rainyDays.append(numberOfDays(in: sequence, matching: "🌧"))
        }
        
        // although randomly generated, the number will hopefully be close after this many runs
        XCTAssertEqualWithAccuracy(average(numbers: sunnyDays), average(numbers: rainyDays), accuracy: 0.5)
        
    }
    
    // test helpers
    func numberOfDays(in sequence: [Weather], matching day: Weather) -> Int {
        return sequence.filter({ d in
            d == day
        }).count
    }
    
    func average(numbers: [Int]) -> Double {
        return Double(numbers.reduce(0,+))/Double(numbers.count)
    }
    
    /*
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }*/
    
}
