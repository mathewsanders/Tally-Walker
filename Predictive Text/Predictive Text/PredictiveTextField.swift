//
//  PredictiveTextField.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import UIKit
import Tally

class PredictiveTextField: UITextField {
    
    let seperatorCharacters = CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)
    
    /// A Tally model of Strings.
    var model: Tally<String>
    
    /// A Tally store backed by Core Data so that updates to the model persist between app sessions.
    let store: CoreDataTallyStore<String>
    
    private var contextualInputAccessoryView: InputAccessoryView?
    
    /// An array of words based on the current input of the textfield.
    var words: [String] {
        if let text = text?.trimmingCharacters(in: seperatorCharacters), text != "" {
            let sequence = text.components(separatedBy: seperatorCharacters)
            return sequence
        }
        return []
    }
    
    required init?(coder aDecoder: NSCoder) {
        
        // Attempt to grab a sqlite database from the app bundle and use it to populate the tally
        // store the first time the app runs.
        // In this case Trained.sqlite has been populated from the first chapter of the book 
        // 'The Picture of Dorian Gray'. See training-data.txt for the actual text that was
        // used.
        do {
            let archive = try CoreDataStoreInformation(sqliteStoreNamed: "Trained", in: .mainBundle)
            store = try CoreDataTallyStore<String>(named: "PredictiveModel", fillFrom: archive)
        }
        catch let error {
            print(error)
            return nil
        }
        
        // set up model
        model = Tally(representing: TallySequenceType.continuousSequence, ngram: .bigram)
        model.store = AnyTallyStore(store)
        
        super.init(coder: aDecoder)
        
        // set up default keyboard
        keyboardType = .default
        autocorrectionType = .no
        spellCheckingType = .no
        
        // set up input accessory
        contextualInputAccessoryView = InputAccessoryView(withTarget: self)
        inputAccessoryView = contextualInputAccessoryView
        contextualInputAccessoryView?.updateSuggestions()
    }
    
    // learn a new example sentence
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
}

// For Strings to be used with a CoreDataTallyStore we need to have the String type implement 
// the `LosslessConvertible` protocol. This simply tells CoreDataTallyStore how a String
// should be represented within a Core Data store (which of course, is as a 'String').
extension String: LosslessConvertible {
    public var losslessRepresentation: CoreDataTallyStoreLosslessRepresentation {
        return .string(self)
    }
    
    public init?(_ representation: CoreDataTallyStoreLosslessRepresentation) {
        if case let .string(stringValue) = representation {
            self = stringValue
        }
        else { return nil }
    }
}
