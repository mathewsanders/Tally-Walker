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
    
    let store: AnyTallyStore<String>
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
        guard let archiveUrl = Bundle.main.url(forResource: "Trained", withExtension: "sqlite") else {
            print("could not load coredata archive from bundle")
            return nil
        }
        
        do {
            store = try AnyTallyStore(CoreDataTallyStore<String>(named: "PredictiveModel", fillFrom: .sqliteStore(at: archiveUrl)))
        }
        catch let error {
            print(error)
            return nil
        }
        
        // set up model
        model = Tally(representing: TallySequenceType.continuousSequence, ngram: .bigram)
        model.store = store
        
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
