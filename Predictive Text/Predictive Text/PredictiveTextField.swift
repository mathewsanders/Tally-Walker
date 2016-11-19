//
//  PredictiveTextField.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import UIKit
import Tally

extension String: LosslessTextConvertible {}

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
        
        // set up model and store
        guard let storeUrl = Bundle.main.url(forResource: "Dorian-Gray", withExtension: "sqlite") else {
            return nil
        }
        
        store = CoreDataTallyStore<String>(named: "PredictiveTextModelStore", restoreFrom: storeUrl)
        
        //store = CoreDataTallyStore<String>(named: "PredictiveTextModelStore")
        model = Tally(representing: TallySequenceType.continuousSequence, ngram: .bigram)
        model.store = AnyTallyStore(store)
        
        super.init(coder: aDecoder)
        
        dump(model.distributions())
        
        // set up default keyboard
        keyboardType = .default
        autocorrectionType = .no
        spellCheckingType = .no
        
        // set up input accessory
        contextualInputAccessoryView = InputAccessoryView(withTarget: self)
        inputAccessoryView = contextualInputAccessoryView
        contextualInputAccessoryView?.updateSuggestions()
    }
    
    deinit {
        store.save()
    }
    
    func learn(example: String) {
        let sequence = example.trimmingCharacters(in: seperatorCharacters).components(separatedBy: seperatorCharacters)
        model.observe(sequence: sequence)
        store.save()
    }
    
    func updateSuggestions() {
        contextualInputAccessoryView?.updateSuggestions()
    }
}
