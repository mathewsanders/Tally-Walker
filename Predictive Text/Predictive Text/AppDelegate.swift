//
//  AppDelegate.swift
//  Predictive Text
//
//  Created by Mathew Sanders on 11/12/16.
//  Copyright © 2016 Mathew Sanders. All rights reserved.
//

import UIKit
import Tally

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func loadData() {
        
        let store = CoreDataTallyStore<String>(named: "Dorian-Gray")
        var model = Tally<String>(representing: .continuousSequence, ngram: .bigram)
        model.store = AnyTallyStore(store)
        
        let lines = array(from: "The-Picture-of-Dorian-Gray")
        let seperators = CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters)
        
        print("loading....", lines.count)
        let total = Double(lines.count)
        var count = 0.0
        
        for line in lines {
            count += 1
            let percent = Int(100*(count/total))
            
            let normalized = normalize(text: line)
            if normalized != "" {
                
                let words = normalized.components(separatedBy: seperators).filter({ word in return !word.isEmpty })
                print(percent, words)
                
                model.observe(sequence: words)
            }
        }
        // can take a few minutes for saves to complete
        // TODO: Investigate if I'm doing something that's slowing down save performance 
    }
    
    func array(from fileName: String) -> [String] {
        guard let path = Bundle.main.path(forResource: fileName, ofType: "txt") else { return [] }
        do {
            let content = try String(contentsOfFile:path, encoding: String.Encoding.utf8)
            return content.components(separatedBy: CharacterSet.newlines)
        } catch { return [] }
    }
    
    func normalize(text: String) -> String {
        return text.lowercased().trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet.punctuationCharacters))
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        //loadData()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

