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
    var model: Tally<String> = Tally(representing: TallySequenceType.continuousSequence, ngram: .trigram)
    
    private lazy var contextualInputAccessoryView: InputAccessoryView = { [unowned self] in
        let inputAccessory = InputAccessoryView(withTarget: self)
        return inputAccessory
    }()
    
    var words: [String] {
        if let text = text?.trimmingCharacters(in: seperatorCharacters), text != "" {
            let sequence = text.components(separatedBy: seperatorCharacters)
            return sequence
        }
        return []
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        // set up default keyboard
        keyboardType = .default
        autocorrectionType = .no
        spellCheckingType = .no
        
        // train model with some examples
        model.observe(sequence: "the cat in the hat sat on the mat".components(separatedBy: seperatorCharacters))
        model.observe(sequence: "the quick brown fox jumped over the fence".components(separatedBy: seperatorCharacters))
        
        // set up input accessory
        inputAccessoryView = contextualInputAccessoryView
        contextualInputAccessoryView.updateSuggestions()
        
    }
    
    func learn(example: String) {
        let sequence = example.trimmingCharacters(in: seperatorCharacters).components(separatedBy: seperatorCharacters)
        model.observe(sequence: sequence)
    }
    
    func updateSuggestions() {
        contextualInputAccessoryView.updateSuggestions()
    }
}
