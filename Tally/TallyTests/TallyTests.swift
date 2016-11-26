// TallyTests.swift
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

import XCTest
import Tally

class TallyTests: XCTestCase {
    
    typealias Weather = Character
    let equalSunnyRainyDays: [Weather] = ["🌧","🌧","🌧","🌧", "☀️","☀️","☀️","☀️"]
    var continuousModel = Tally<Weather>()
    var continuousWalker: Walker<Weather>!
    
    override func setUp() {
        super.setUp()
        
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
            //print(sequence)
            XCTAssertTrue(sequence.count == fillSize, "Fill should have generated \(fillSize) items")
            
            sunnyDays.append(numberOfDays(in: sequence, matching: "☀️"))
            rainyDays.append(numberOfDays(in: sequence, matching: "🌧"))
        }
        
        // although randomly generated, the number will hopefully be close after this many runs
        XCTAssertEqualWithAccuracy(average(numbers: sunnyDays), average(numbers: rainyDays), accuracy: 1.0)
        
    }
    
    func testDiscreteModel() {
        
        // captions should contain 4141 captions from New Yorker cartoon submissions
        let captions = array(from: "new-yorker-captions")
        XCTAssertTrue(captions?.count == 4141, "Error loading captions")
        
        var startingWords: [String: Bool] = [:]
        var allWords: [String: Bool] = [:]
        
        var model = Tally<String>(representing: .discreteSequence, ngram: .ngram(depth: 2))
        
        for caption in captions! {
            
            let words = caption.components(separatedBy: CharacterSet.whitespaces).flatMap({ word in normalize(text: word) })
            startingWords[words[0]] = true
            
            model.startSequence()
            
            for word in words {
                model.observe(next: word)
                allWords[word] = true
            }
            
            model.endSequence()
        }
        
        XCTAssertTrue(model.startingItems().count == startingWords.keys.count, "Problem with starting words in model")
        XCTAssertTrue(model.distributions().count == allWords.keys.count, "Problem with number of words in model")
        
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
    
    func array(from fileName: String) -> [String]? {
        guard let path = Bundle(for: TallyTests.self).path(forResource: fileName, ofType: "txt") else { return nil }
        do {
            let content = try String(contentsOfFile:path, encoding: String.Encoding.utf8)
            return content.components(separatedBy: CharacterSet.newlines)
        } catch { return nil }
    }
    
    func normalize(text: String) -> String {
        return text.lowercased().trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters))
    }
    
}
