//
//  PredictiveTextField+Classes.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import Tally

extension PredictiveTextField {
    
    class InputAccessoryView: UIView {
        
        let whitespaces = CharacterSet.whitespaces
        let suggestionsStack = UIStackView()

        var suggestions: [String] = []
        
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
        
        // text updated
        func valueChanged(textfield: UITextField) {
            updateSuggestions()
        }
        
        // update the suggestions shown in the accessory view
        func updateSuggestions() {
            
            let lastWord = target.words.last ?? ""
            let nextElements = target.model.elementProbabilities(after: lastWord).filter(onlyItemNodes).sorted(by: orderProbabilities)
            
            let allSuggestions = nextElements.isEmpty ? target.model.startingElements().sorted(by: orderProbabilities) : nextElements
            
            suggestions = allSuggestions.prefix(3).flatMap({ $0.element.item })
            
            suggestionsStack.arrangedSubviews.forEach({ subview in
                suggestionsStack.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            })
            
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
