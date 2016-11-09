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
// - for models of discrete sequences `nil` represents the end of a sequence

// End the current random walk so that the next call to `next()` returns the first item in a new walk.
walker.endWalk()

// iterate over items
for item in walker {
    // ... do something with an individual item
}

// generate an array of up to 10 items
let tenItems = walker.fill(request: 10)
// - for models of continuous sequences the array may be less than the requested length
// - for models of discrete sequences the array will be the requested length

```

## Saving Models

The loading of Tally models in and out of a store are handled by an object that creates a bridge between a type of `Tally` item and a compatible 'store'.

You'll need to create an implementation of the store that handles both the specific type of object represented by your model (e.g. a String, Int, or a custom object) and how the store persists data (e.g. writing to a file, saving to a database), but implementing some simple protocols gives you a jump-start to writing your store.

First, here's an example of loading a `Tally<String>` model into a `StringPlistStore` store, which like the name suggests, persists information about a model of `String` items by writing to a plist file.

### Saving a model to a plist

```Swift
// Create a bridge between an `Item` and an implementation of `TallyFlatStoreType`
let bridge = TallyBridge<String, StringPlistStore>()

// load the `Tally` model into a `StringStore`
let store = bridge.load(model: model)

// save the store
store.save(to: "data.plist")
```

### Loading a model from a plist

```Swift
// Create a bridge between an `Item` and an implementation of `TallyFlatStoreType`
let bridge = TallyBridge<String, StringPlistStore>()

// load the store
let store = StringStore(from: "data.plist")

let model = bridge.load(store: store)

// model is ready to interact with...

```

### Creating a store

A `Tally` model represents ngrams internally as a tree of nodes where each node may be a literal item (e.g. the text "hello"), or represent the start or end of a sequence.

`TallyFlatStoreType` defines the implementation of a store where information about nodes are accessed through calls to get or set information about a node through a unique identifier.

As long as your store implements these requirements as defined, and provides a sensible way to save or retrieve its internal state then the TallyBridge provides the mechanics of transferring information between model and store, and vice versa.

```Swift
public protocol TallyFlatStoreType {

    associatedtype StoreItem: Hashable

    /// A unique reference representing a node.
    typealias Id = String // using UUID

    /// A tuple that represents a node in a tree representing a structure of ngrams.
    /// - `node` is a wrapper for the item in the ngram which may represent a literal item, or also a marker to represent the start, or end of a sequence. It is up to the implementation to ensure that these markers are suitably accounted for in the store.
    /// - `count` is an integer representing the number of occurrences of the node.
    /// - `childIds` an array of ids of children of this node.
    typealias StoreValue = (node: Node<StoreItem>, count: Int, childIds: [Id])

    /// The type of sequence of the model that this store holds.
    var sequenceType: TallySequenceType { get }

    /// The size of the ngram of the model that this store holds.
    var ngramType: NgramType { get }

    /// Ids for children of the root node.
    var rootChildIds: [Id] { get }

    /// The store needs to be initializable without any parameters.
    init(sequenceType: TallySequenceType, ngramType: NgramType, rootChildIds: [Id])

    /// Add information about a node to the store.
    ///
    /// - parameter id: the Id of the node, used as an index.
    /// - parameter value: the node, number of occurrences, and childIds of the node.
    mutating func add(id: Id, value: StoreValue)

    /// Get the node, number of occurrences, and Ids of child nodes for the node with the id.
    /// Returns nil if no node found in the store with that id.
    /// - parameter id: the Id of the node to retrieve.
    func get(id: Id) -> StoreValue?

}
```


If your model items can be safely transformed into a textual format without loss of information, extend your items to implement `NodeRepresentableWithTextType`.

For most items this will be a trivial extension on your item type, for example for a model of type Tally<String>:

```Swift
extension String: NodeRepresentableWithTextType {
    public init?(_ text: String) {
        self = text
    }

    public var textValue: String {
        return self.description
    }
}
```

This gives your implementation of `TallyFlatStoreType` access to two convenience methods to translate between a node, and a textual representation of the node which is ready to be entered into a store.

Get a text representation of the node:
`func textRepresentation(from node: Node<StoreItem>) -> String?`

Get a node from the text representation:
`func node(from textRepresentation: String) -> Node<StoreItem>?`


## Roadmap

- [x] Build models from observed training examples
- [x] Model either continuous or discrete sequences
- [x] Option to set the size of n-grams used
- [x] Generic type - works on any `Hashable` item
- [x] List probability for next item in sequence
- [ ] List probability for next sequence of items in sequence
- [ ] List most frequent n-grams
- [x] Export/import model (maybe json, plist)
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

Made with :heart: by [@permakittens](http://twitter.com/permakittens)

## Contributing

Feedback, or contributions for bug fixing or improvements are welcome. Feel free to submit a pull request or open an issue.

## License

MIT
