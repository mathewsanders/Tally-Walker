//
//  ViewController.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import UIKit

class ViewController: UITableViewController, UITextFieldDelegate {

    @IBOutlet weak var predictiveTextField: PredictiveTextField!
    
    var examples: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        predictiveTextField.delegate = self
        predictiveTextField.becomeFirstResponder()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if textField == predictiveTextField, let example = textField.text {
            examples.insert(example, at: 0)
            
            predictiveTextField.learn(example: example)
            predictiveTextField.text = nil
            predictiveTextField.updateSuggestions()
            
            tableView.reloadData()
            
        }
        
        return true
    }
    
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

