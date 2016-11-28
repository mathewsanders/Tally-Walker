//
//  PredictiveTextField.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import UIKit
import Tally

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

class PredictiveTextField: UITextField {
    
    let seperatorCharacters = CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)
    
    let store: CoreDataTallyStore<String>
    var model: Tally<String>
    
    private var contextualInputAccessoryView: InputAccessoryView?
    
    var words: [String] {
        if let text = text?.trimmingCharacters(in: seperatorCharacters), text != "" {
            let sequence = text.components(separatedBy: seperatorCharacters)
            return sequence
        }
        return []
    }
    
    required init?(coder aDecoder: NSCoder) {
        
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
    
    func learn(example: String) {
        
        let sequence = example.trimmingCharacters(in: seperatorCharacters).components(separatedBy: seperatorCharacters)
        
        model.observe(sequence: sequence) {
            self.store.save(completed: {
                self.updateSuggestions()
            })
        }
    }
    
    func updateSuggestions() {
        contextualInputAccessoryView?.updateSuggestions()
    }
}
