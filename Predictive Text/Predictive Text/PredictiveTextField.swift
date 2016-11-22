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
    public func losslessRepresentation() -> String {
        return self
    }
}

class PredictiveTextField: UITextField {
    
    let seperatorCharacters = CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)
    
    var store: CoreDataTallyStore<String>
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
        
        // set up store
        guard let archivedStore = Bundle.main.url(forResource: "Dorian-Gray-smart", withExtension: "sqlite") else { return nil }
        store = CoreDataTallyStore<String>(named: "PredictiveTextModelStore", fillFrom: archivedStore)
        //store = CoreDataTallyStore<String>(named: "PredictiveTextModelStore")
        
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
            DispatchQueue.main.async {
                self.updateSuggestions()
            }
        }
    }
    
    func updateSuggestions() {
        contextualInputAccessoryView?.updateSuggestions()
    }
}
