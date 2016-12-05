// To use this playground with the Tally framework: 
//
// 1. Open `Tally.xworkspace` from the playgrounds folder
// 2. Build project
// 3. That's it! Tally should now be avaliable in this playground.

import Tally

typealias Weather = Character

var weatherModel = Tally<Weather>()

// Observe sequences of items to build the probability model
weatherModel.observe(sequence: ["🌧","🌧","🌧","🌧", "☀️","☀️","☀️","☀️"])

// Check the overall distributions of items observed
weatherModel.distributions()

// Check to see what items are expected to follow a specific item
weatherModel.elementProbabilities(after: "🌧")
weatherModel.elementProbabilities(after: "☀️")

// Create a walker from a frequency model
var walker = Walker(model: weatherModel)

// Create four weeks of 7 day forecasts
for _ in 0..<4 {
    let forecast = walker.fill(request: 7)
    print(forecast)
}

// To take a peek at the underlying structure of the probability model:
// dump(weatherModel)
