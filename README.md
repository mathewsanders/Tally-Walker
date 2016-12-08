<img src="assets/tally-walker-logo.png" alt="Tally & Walker logo" width="60">

# Tally & Walker

Tally & Walker is a lightweight Swift library for building probability models of n-grams.

## Quick example

Build a frequency model of n-grams by observing example sequences:

````Swift

// Create a model out of any type that adopts the `Hashable` protocol
var weatherModel = Tally<Character>()

// Observe sequences of items to build the probability model
weatherModel.observe(sequence: ["🌧","🌧","🌧","🌧", "☀️","☀️","☀️","☀️"])

// Check the overall distributions of items observed
weatherModel.distributions()
// Returns:
// [(probability: 0.5, element: "🌧"),
//  (probability: 0.5, element: "☀️")]

// Check to see what items are expected to follow a specific item  
weatherModel.elementProbabilities(after: "🌧")
// Returns:
// [(probability: 0.75, element: "🌧"),
//  (probability: 0.25, element: "☀️")]

weatherModel.elementProbabilities(after: "☀️")
// Returns:
// [(probability: 0.75, element: "☀️"),
//  (probability: 0.25, element: .unseenTrailingItems)]
//
// `.unseenTrailingItems` is an element, which instead of representing an
// item, is a marker that indicates that the sequence continues but, based
// on the sequences we have observed, we don't know what items come next

````

Generate new sequences based off a random walk using through the probability model:

````Swift

// Create a walker from a frequency model
var walker = Walker(model: weatherModel)

// Create four weeks of 7 day forecasts
for _ in 0..<4 {
  let forecast = walker.fill(request: 7)
  print(forecast)
}

// Prints:
// ["☀️", "☀️", "🌧", "🌧", "🌧", "🌧", "🌧"]
// ["☀️", "☀️", "🌧", "☀️", "☀️", "🌧", "☀️"]
// ["🌧", "🌧", "☀️", "☀️", "☀️", "☀️", "☀️"]
// ["☀️", "☀️", "☀️", "☀️", "☀️", "☀️", "☀️"]
//
// Although the overall distribution of rainy days and sunny days are equal
// we don't want to generate a sequence based off a coin flip. Instead we
// except that the weather tomorrow is more likely the same as the weather
// today, and that we will find clusters of rainy and sunny days but that
// over time the number of rainy days and sunny days will approach each other.

````

## Documentation

- [Tally options](Documentation/1. Tally.md)
- [Saving models](Documentation/2. Saving models.md)
- [Normalizing items](Documentation/3. Normalizing items.md)
- [Using Tally with complex objects](Documentation/4. Using Tally with complex objects.md)
- [Walker options](Documentation/5. Walker.md)

## Examples

- [Weather Playground](/Examples/Playgrounds) A Playground with the weather example used above
- [Predictive Text](/Examples/Predictive Text) A proof-of-concept using Tally to re-create iOS QuickType predictive suggestions.

## Roadmap

- [x] Build models from observed training examples
- [x] Model either continuous or discrete sequences
- [x] Option to set the size of n-grams used
- [x] Generic type - works on any `Hashable` item
- [x] List probability for next item in sequence
- [ ] List probability for next sequence of items in sequence
- [ ] List most frequent n-grams
- [x] Persist model using Core Data
- [ ] Add pseudocounts to smooth infrequent or unseen n-grams
- [x] Normalize items as they are observed
- [ ] Tag observed sequences with metadata/category to provide context
- [ ] Approximate matching to compare item sequences
- [ ] Include common sample training data
- [x] Generate new sequence from random walk
- [ ] Generate sequences from biased walk
- [ ] Semi-random walk that biases towards a target length of a discrete sequence

## Requirements

- Xcode 8.0
- Swift 3.0
- Target >= iOS 10.0

## Author

Made with :heart: by [@permakittens](http://twitter.com/permakittens)

## Contributing

Feedback, or contributions for bug fixing or improvements are welcome. Feel free to submit a pull request or open an issue.

## License

MIT
