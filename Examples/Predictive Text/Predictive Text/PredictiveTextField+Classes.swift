//
//  PredictiveTextField+Classes.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import UIKit
import AVFoundation
import Tally

extension PredictiveTextField {
    
    /// An view used by a PredictiveTextField as it's input accessory view.
    ///
    /// When the text field value changes, this view looks uses the last word
    /// entered in the text field, and displays up to three words that are 
    /// likely to be entered next based on an underlying Tally model.
    final class InputAccessoryView: UIView {
        
        let whitespaces = CharacterSet.whitespaces
        let suggestionsStack = UIStackView()
        
        unowned let target: PredictiveTextField
        
        init(withTarget target: PredictiveTextField) {
            self.target = target
            super.init(frame: CGRect(origin: .zero, size: CGSize(width: UIViewNoIntrinsicMetric, height: 42)))
            
            self.target.addTarget(self, action: #selector(InputAccessoryView.valueChanged(textfield:)), for: UIControlEvents.editingChanged)
            
            backgroundColor = UIColor(red: 187/255, green: 194/255, blue: 202/255, alpha: 1.0)
            
            suggestionsStack.distribution = .fillEqually
            suggestionsStack.alignment = .fill
            suggestionsStack.spacing = 0.0
            suggestionsStack.translatesAutoresizingMaskIntoConstraints = false
            
            self.addSubview(suggestionsStack)
            
            suggestionsStack.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 0).isActive = true
            suggestionsStack.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 0).isActive = true
            suggestionsStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 0).isActive = true
            suggestionsStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0).isActive = true
        }
        
        deinit {
            self.target.removeTarget(self, action: nil, for: UIControlEvents.allEditingEvents)
        }
        
        // text updated
        func valueChanged(textfield: UITextField) {
            updateSuggestions()
        }
        
        // update the suggestions shown in the accessory view
        func updateSuggestions() {
            
            // get the last word currently in the text field
            let lastWord = target.words.last ?? ""
            
            // Get the next words based on the last word entered
            // the model is build around bigrams, so it's not possible to use anything
            // but a single word to determine what the next word might be.
            // Using a trigram would allow to look for next words based on the last two words
            // which would likely improve the contextual relevence of the suggestions, but would
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
        
        typealias Probability = (probability: Double, element: NgramElement<String>)
        private func orderProbabilities(lhs: Probability, rhs: Probability) -> Bool {
            return lhs.probability > rhs.probability
        }
        
        private func onlyItemNodes(elementProbability: Probability) -> Bool {
            return elementProbability.element.item != nil
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    // MARK: Inner class
    
    /// A simple subclass to use as a button in the input accessory view.
    class SuggestionButton: UIButton {
        
        let title: String!
        var target: UITextInput!
        var defaultColor: UIColor? = nil
        
        init(title: String, target: UITextInput) {
            
            self.title = title
            self.target = target

            super.init(frame: .zero)
            commonSetup()
        }
        
        private func commonSetup() {
            
            setTitleColor(.white, for: .normal)
            setTitleColor(.black, for: .highlighted)
            setTitle(title, for: .normal)
            
            backgroundColor = defaultColor
            
            addTarget(self, action: #selector(SuggestionButton.prepare), for: .touchDown)
            addTarget(self, action: #selector(SuggestionButton.trigger), for: .touchUpInside)
        }
        
        func prepare() {
            UIDevice.current.playInputClick()
            backgroundColor = .white
        }
        
        func trigger() {
            
            UIView.animate(withDuration: 0.25, delay: 0.0, options: .allowUserInteraction, animations: {
                self.backgroundColor = self.defaultColor
            }, completion: nil)
            
            target.insertText(title+" ")
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
