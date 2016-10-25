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
// [(probability: 0.5, item: "🌧"),
//  (probability: 0.5, item: "☀️")]

// Check to see what items are expected to follow a specific item  
weatherModel.itemProbabilities(after: "☀️")
// Returns:
// [(probability: 0.75, item: "☀️"),
//  (probability: 0.25, item: "🌧")]

weatherModel.itemProbabilities(after: "🌧")
// Returns:
// [(probability: 0.75, item: "🌧"),
//  (probability: 0.25, item: .unseenItems)]
//
// `.unseenItems` is a marker to say that the sequence continues but, based
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

## Using Tally

### Creating Model

By default, `Tally` creates a model to represent continuous sequences, using a bi-gram (which is an n-gram with two items).

Both of these default options can be changed when creating a new model:

```Swift

// create a model to represent a discrete sequence using a 3-gram
var model = Tally<String>(representing: .discreteSequence, ngram: .trigram)

// create a model to represent a continuous sequence using a 4-gram
var model = Tally<String>(representing: .continuousSequence, ngram: ngram(4))

```

Choose `.continuousSequence` when your sequences have no arbitrary beginning or end, or when the beginning and end of an observed sequence doesn't mean anything.

Choose `.discreteSequence` when you want the items that start and end a sequence to have significance.

Take caution with using larger n-grams! Larger n-grams will impact memory and performance. If you can't get your expected outcome using a bigram or trigram it's possible that another approach might be better suited for your purposes.

### Training the model  

If all items in a sequence can't be observed in a single pass, items can be observed individually if you wrap the observations in calls to `startSequence()` and `endSequence()`

```Swift

// load text to model
let tweets: [String] = ["...tweet text here..."]

for tweet in tweets {

  // start a sequence
  model.startSequence()

  // enumerate items and observe them one at a time
  tweet.enumerateSubstrings(in: tweet.startIndex..<tweet.endIndex, options: .byWords, { word, _, _, _ in
    if let word = word {
      model.observe(next: word)
    }
  })

  // end the sequence
  model.endSequence()
}

```

### Getting probabilities

Along with returning the probability of items that follow a single item, it's also possible to look for items that follow a sequence of items, however the length of the sequence that can be searched is limited by the size of the n-gram that the model uses.

```Swift

// Create a model that uses 3-gram
var genes = Tally<Character>(ngram: .trigram)

/* train the model */

// find probabilities of items that follow the item 'C'
genes.itemProbabilities(after: "C")

// Find probabilities of items that follow the sequence 'C-T'  
genes.itemProbabilities(after: ["C", "T"])

// Because this model uses a 3-gram, it's not possible to find probabilities of
// items that follow a sequence longer than two items, instead of returning no
// matches, the model will clamp the sequence to the maximum size that the
// model allows, in this case returning items that follow the sequence 'G-A'
genes.itemProbabilities(after: ["C", "T", "G", "A"])

```

### Using Tally with custom objects

Tally is a generic class that is ready to work on any type that is `Hashable`.
If you want to use Tally with your custom objects, just make sure that complies to the `Hashable` protocol:

````Swift

struct Cat: Hashable {

  let name: String

  // Hashable requires a `hashValue` property
  var hashValue: Int {
    return name.hashValue
  }

  // Hashable requires Equatable, which requires a == function to be defined
  static func == (lhs: Cat, rhs: Cat) -> Bool {
    return lhs.name == rhs.name
  }
}

// now we can create an n-gram out of `Cat` objects
var catsgram = Tally<Cat>()

````

## Using Walker

### Creating the walker

Along with the probability model to use for random walks, you can also specify how many items to use to determine the next step.  

```Swift

// Markov chain represents a walk where only the last step is considered
var markovWalker = Walker(model: model, walkOptions: .markovChain)

// Match model is the default option which will automatically use the largest
// number of steps based on the size of n-gram that the model uses
var walker = Walker(model: model, walkOptions: .matchModel)

// Alternatively, you can request a specific number of steps
var twoStepWalker = Walker(model: model, walkOptions: .steps(2))

```

### Generating sequences

Sequences are generated with a random walk looking at the last _n_ steps as specified by the walk options.
`Walker` is a type of `Sequence` meaning that you can iterate over it like you would any collection:

```Swift

var walker = Walker(model: model)

// get the next item by a random walk
let item = walker.next()
// returns an optional:
// - for models of continuous sequences this should always return an item
// - for models of discrete sequences, nil represents the end of a sequence

// End the current random walk so that the next call to `next()` returns the first item in a new walk.
walker.endWalk()

// iterate over items
for item in walker {
    // ... do something with an individual item
}

// generate an array of up to 10 items
let tenItems = walker.fill(request: 10)
// - for models of continuous sequences the array may be less than the requested length
// - for models of discrete sequences, the array will be the requested length

```

## Roadmap

- [x] Build models from observed training examples
- [x] Model either continuous or discrete sequences
- [x] Option to set the size of n-grams used
- [x] Generic type - works on any `Hashable` item
- [x] List probability for next item in sequence
- [ ] List probability for next sequence of items in sequence
- [ ] List most frequent n-grams
- [ ] Export/import model (maybe json, plist)
- [ ] Persist model (maybe NSCoding, Core Data)
- [ ] Add pseudocounts to smooth infrequent or unseen n-grams
- [ ] Normalize items as they are observed while keeping original value and count
- [ ] Tag observed sequences with metadata/category to provide context
- [ ] Approximate matching to compare item sequences
- [ ] Include common sample training data
- [x] Generate new sequence from random walk
- [ ] Generate sequences from biased walk
- [ ] Semi-random walk that biases towards a target length of a discrete sequence

## Requirements

- Xcode 8.0+
- Swift 3.0+

## Author

Made with :heart: in NYC by @permakittens

## Contributing

Contributions for bug fixing or improvements are welcome. Feel free to submit a pull request.

## License

MIT
