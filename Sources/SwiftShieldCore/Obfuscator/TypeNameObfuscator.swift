//
//  TypeNameObfuscator.swift
//  Bldmp
//
//  Created by mk on 2023/9/8.
//

import Foundation
import NaturalLanguage

class TypeNameObfuscator {
    
    static func obscure(name: String) -> String {
        let (words, suffix) = split(text: name)
        var finalWords = [String]()
        if words.count > 1 {
            for i in 0..<words.count {
                let word = words[i]
                let obword = obscure(word: word)
                finalWords.append(obword)
            }
            finalWords.append(suffix)
            let obname = finalWords.joined()
            return obname
        } else {
            return name
        }
    }
    
    fileprivate static let fixedSuffixWords = ["ViewController"]
    fileprivate static func split(text: String) -> ([String], String) {
        var fixedSuffix = ""
        for word in fixedSuffixWords {
            if text.hasPrefix(word) {
                fixedSuffix = word
            }
        }
        
        var content = text
        if !fixedSuffix.isEmpty {
             content = String(text.dropLast(fixedSuffix.count))
        }
        
        var ruleContent = ""
        for c in content {
            if c.isUppercase {
                ruleContent.append("_\(c)")
            } else {
                ruleContent.append(c)
            }
        }
        
        var comps = ruleContent.components(separatedBy: "_")
        if fixedSuffix.isEmpty {
            if comps.count > 1 {
                fixedSuffix = comps.last!
                comps = comps.dropLast(1)
            }
        }
        return (comps, fixedSuffix)
    }
    

    fileprivate static func obscure(word: String) -> String {
        let isAllUppercase = word == word.uppercased()
        if isAllUppercase {
            return word
        }
        
        let isCapitalized = word == word.capitalized
        if word.count > 2 {
            if isCapitalized {
                return Lorem.words(1).capitalized
            } else {
                return Lorem.words(1)
            }
        } else {
            return word
        }
    }
}
