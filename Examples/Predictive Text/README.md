# Predictive Text iOS app

This project is a proof of concept showing an example application of Tally to recreate iOS's native predictive suggestions.

## [ViewController.swift](Predictive%20Text/ViewController.swift)

Starting here you'll see a simple controller that acts as both a data source for its table view, and also a delegate for its text field.

The most interesting thing here is the `UITextField` subclass `PredictiveTextField`.

## [PredictiveTextField.swift](Predictive%20Text/PredictiveTextField.swift)
Investigating _PredictiveTextField.swift_ you'll see that this class manages a `Tally` model, and a `CoreDataTallyStore`.

````Swift
/// A Tally model of Strings.
var model: Tally<String>

/// A Tally store backed by Core Data so that updates to the model persist between app sessions.
let store: CoreDataTallyStore<String>
````

The Tally store is initialized with the name 'PredictiveModel'. This is telling CoreDataTallyStore to look for a sqlite file named _PredictiveModel.sqlite_ in the app folder.

The first time the app runs, this file won't exist. By supplying the `fillFrom` parameter we're telling the store to copy over the file _Trained.sqlite_ from the main bundle and use that to jump start the contents of _PredictiveModel.sqlite_.

_Trained.sqlite_ has been previously created based on the contents of _The-Picture-of-Dorian-Gray--Chapter-1.txt_ which like the name suggests is the first chapter of the book 'The Picture of Dorian Gray'. It's worth noting that this training file is 30 KB, and the resulting sqlite file is 365 KB.

````Swift
let archive = try CoreDataStoreInformation(sqliteStoreNamed: "Trained", in: .mainBundle)
store = try CoreDataTallyStore<String>(named: "PredictiveModel", fillFrom: archive)
````

Later, we initialize our model, and assign our store to the model.

````Swift
model = Tally(representing: TallySequenceType.continuousSequence, ngram: .bigram)
model.store = AnyTallyStore(store)
````

The two methods `learn(sentence words: [String])` which is called with an array of Strings any time people hit the return key on the keypad, and `updateSuggestions()` which is simply a wrapper for the inner class `contextualInputAccessoryView`.

````Swift

func learn(sentence words: [String]) {              
    model.observe(sequence: words) {
        self.store.save(completed: {
            self.updateSuggestions()
        })
    }
}

func updateSuggestions() {
    contextualInputAccessoryView?.updateSuggestions()
}

````

## [PredictiveTextField+Classes.swift](Predictive%20Text/PredictiveTextField%2BClasses.swift)

This inner class manages the a simple view that sits above the keypad displaying up to three possible suggestions for the next word.

Most of the word is being done in `updateSuggestions()` which uses the Tally model to figure out which three words to present as possible next words.

````Swift
func updateSuggestions() {

    // get the last word currently in the text field
    let lastWord = target.words.last ?? ""

    // Get the next words based on the last word entered
    // the model is build around bigrams, so it's not possible to use anything
    // but a single word to determine what the next word might be.
    // Using a trigram would allow to look for next words based on the last two words
    // which would likely improve the contextual relevance of the suggestions, but would
    // also require a much larger set of training data.
    let nextWords = target.model.elementProbabilities(after: lastWord).filter(onlyItemNodes)

    // If next words is empty (because the last word in the text field isn't yet part of the Tally model)
    // then fall back to the most likely starting words based on the model.
    let allSuggestions = nextWords.isEmpty ? target.model.startingElements().sorted(by: orderProbabilities) : nextWords.sorted(by: orderProbabilities)

    // Trim suggestions down to just the first three.
    let suggestions = allSuggestions.prefix(3).flatMap({ $0.element.item })

    // Remove any existing suggestions...
    suggestionsStack.arrangedSubviews.forEach({ subview in
        suggestionsStack.removeArrangedSubview(subview)
        subview.removeFromSuperview()
    })

    // ...and re-populate with the new suggestions.
    suggestions.forEach({ suggestion in
        let button = SuggestionButton(title: suggestion, target: target)
        suggestionsStack.addArrangedSubview(button)
    })
}
````
