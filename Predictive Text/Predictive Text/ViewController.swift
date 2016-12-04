//
//  ViewController.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import UIKit

class ViewController: UITableViewController, UITextFieldDelegate {
    
    // A subclass of UITextField that manages a Tally model of words and sets up its inputAccessoryView 
    // to display possible next words based on the model.
    @IBOutlet weak var predictiveTextField: PredictiveTextField!
    
    // The example sentences that you've entered during this run of the app
    var examples: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        predictiveTextField.delegate = self
        predictiveTextField.becomeFirstResponder()
    }
    
    // A textfield's return button has been hit
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if textField == predictiveTextField, let example = textField.text, example != "" {
            
            // have the text field learn this new example and clear the textfield for
            // new text to be entered
            predictiveTextField.learn(sentence: predictiveTextField.words)
            predictiveTextField.text = nil
            
            // add this text into examples and reload the table
            examples.insert(example, at: 0)
            tableView.reloadData()
            
        }
        
        return true
    }
    
    // Display the example sentences entered
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return examples.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ExampleCell", for: indexPath)
        
        let example = examples[indexPath.row]
        cell.textLabel?.text = example
        
        return cell
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}

