import Foundation

final class SourceKitObfuscator: ObfuscatorProtocol {
    enum WordType: String {
        case random, words
    }
    
    let sourceKit: SourceKit
    let logger: LoggerProtocol
    let dataStore: SourceKitObfuscatorDataStore
    let ignorePublic: Bool
    let namesToIgnore: Set<String>
    let modulesToIgnore: Set<String>
    let fileNamesToIgnore: Set<String>
    let excludeTypes: Set<SourceKit.DeclarationType>
    let wordType: WordType
    weak var delegate: ObfuscatorDelegate?

    init(sourceKit: SourceKit, logger: LoggerProtocol, dataStore: SourceKitObfuscatorDataStore, namesToIgnore: Set<String>, ignorePublic: Bool, wordType: String?, modulesToIgnore: Set<String>, fileNamesToIgnore: Set<String>, excludeTypes: Set<String>) {
        self.sourceKit = sourceKit
        self.logger = logger
        self.dataStore = dataStore
        self.ignorePublic = ignorePublic
        self.namesToIgnore = namesToIgnore
        self.modulesToIgnore = modulesToIgnore
        self.fileNamesToIgnore = fileNamesToIgnore
        var tmpTypes = Set<SourceKit.DeclarationType>()
        for typeStr in excludeTypes {
            if let type = SourceKit.DeclarationType(rawValue: typeStr) {
                tmpTypes.insert(type)
            }
        }
        self.excludeTypes = tmpTypes
        self.wordType = WordType(rawValue: wordType ?? "") ?? .words
    }

    var requests: sourcekitd_requests! {
        sourceKit.requests
    }

    var keys: sourcekitd_keys! {
        sourceKit.keys
    }
}

// MARK: Indexing

extension SourceKitObfuscator {
    func registerModuleForObfuscation(_ module: Module) throws {
        let compilerArguments = SKRequestArray(sourcekitd: sourceKit)
        module.compilerArguments.forEach(compilerArguments.append(_:))
        try module.sourceFiles.sorted { $0.path < $1.path }.forEach { file in
            if !fileNamesToIgnore.contains(file.name) {
                logger.log("--- Indexing: \(file.name)")
                let req = SKRequestDictionary(sourcekitd: sourceKit)
                req[keys.request] = requests.indexsource
                req[keys.sourcefile] = file.path
                req[keys.compilerargs] = compilerArguments
                let response = try sourceKit.sendSync(req)
                logger.log("--- Preprocessing indexing result of: \(file.name)")
                response.recurseEntities { [unowned self] dict in
                    preprocess(declarationEntity: dict, ofFile: file, fromModule: module)
                }
                logger.log("--- Processing indexing result of: \(file.name)")
                try response.recurseEntities { [unowned self] dict in
                    if ignorePublic, dict.isPublic {
                        return
                    }
                    try process(declarationEntity: dict, ofFile: file, fromModule: module)
                }
                let indexedFile = IndexedFile(file: file, response: response)
                self.dataStore.indexedFiles.append(indexedFile)
            } else {
                logger.log("--- Ignoring file: \(file.name)")
            }
        }
        dataStore.plists = dataStore.plists.union(module.plists)
        dataStore.ibxmls = dataStore.ibxmls.union(module.ibxmls)
    }

    func preprocess(
        declarationEntity dict: SKResponseDictionary,
        ofFile file: File,
        fromModule module: Module
    ) {
        guard let usr: String = dict[keys.usr] else {
            return
        }
        dataStore.fileForUSR[usr] = file
    }

    func process(
        declarationEntity dict: SKResponseDictionary,
        ofFile file: File,
        fromModule module: Module
    ) throws {
        let entityKind: SKUID = dict[keys.kind]!
        guard let kind = entityKind.declarationType() else {
            return
        }
        guard let rawName: String = dict[keys.name],
              let usr: String = dict[keys.usr]
        else {
            return
        }

        let name = rawName.removingParameterInformation

        if namesToIgnore.contains(name) {
            logger.log("* Ignoring \(name) (USR: \(usr)) because its included in ignore-names", verbose: true)
            return
        }
        
        // Skip exclude types
        if excludeTypes.contains(kind) {
            return
        }

        // Skip enum that inherits from CodingKey
        if kind == .enum, let usr: String = dict[keys.usr] {
            let codingKeysUSR: Set<String> = ["s:s9CodingKeyP"]
            if try inheritsFromAnyUSR(
                usr,
                anyOf: codingKeysUSR,
                inModule: module
            ) {
                logger.log("* Ignoring \(name) (USR: \(usr)) because its inherits from CodingKey.", verbose: true)
                return
            } else {
                logger.log("Info: Proceeding with \(name) (USR: \(usr)) because its does not appear to inherit from CodingKey.)", verbose: true)
            }
        }

        // Skip enum elements of CodingKey enum
        if kind == .enumelement, let parentUSR: String = dict.parent[keys.usr] {
            let codingKeysUSR: Set<String> = ["s:s9CodingKeyP"]
            if try inheritsFromAnyUSR(
                parentUSR,
                anyOf: codingKeysUSR,
                inModule: module
            ) {
                logger.log("* Ignoring \(name) (USR: \(usr)) because its parent enum inherits from CodingKey.", verbose: true)
                return
            } else {
                logger.log("Info: Proceeding with \(name) (USR: \(usr)) because its parent enum does not appear to inherit from CodingKey.)", verbose: true)
            }
        }

        // Skip properties of Codable structs
        if kind == .property,
           dict.parent != nil,
           let parentKind: SKUID = dict.parent[keys.kind],
           parentKind.declarationType() == .object
        {
            guard let parentUSR: String = dict.parent[keys.usr] else {
                throw logger.fatalError(forMessage: "Parent of \(usr) doesn't have USR!")
            }

            let codableUSRs: Set<String> = ["s:s7Codablea", "s:SE", "s:Se"]
            if try inheritsFromAnyUSR(
                parentUSR,
                anyOf: codableUSRs,
                inModule: module
            ) {
                logger.log("* Ignoring \(name) (USR: \(usr)) because its parent inherits from Codable.", verbose: true)
                return
            } else {
                logger.log("Info: Proceeding with \(name) (USR: \(usr)) because its parent does not appear to inherit from Codable.)", verbose: true)
            }
        }

        // Skip Core Data entities
        if let related: SKResponseArray = dict[keys.related], related.count > 0, related[0][keys.name] == "NSManagedObject" {
            logger.log("* Ignoring \(name) (USR: \(usr)) because its Core Data entity.", verbose: true)
            return
        }

        // Skip Core Data entity attributes
        if let attributes: SKResponseArray = dict[keys.attributes] {
            if attributes.contains(where: { attribute in
                if let attr: SKUID = attribute[keys.attribute], attr.description == "source.decl.attribute.NSManaged" {
                    return true
                }
                return false
            }) {
                logger.log("* Ignoring \(name) (USR: \(usr)) because its Core Data entity attribute.", verbose: true)
                return
            }
        }

        // Skip "wrappedValue" property in entities that have @propertyWrapper attribute
        if name == "wrappedValue", dict.parent != nil, let attributes: SKResponseArray = dict.parent[keys.attributes] {
            if attributes.contains(where: { attribute in
                if let attr: SKUID = attribute[keys.attribute], attr.description == "source.decl.attribute.propertyWrapper" {
                    return true
                }
                return false
            }) {
                logger.log("* Ignoring \(name) (USR: \(usr)) because its parent has @propertyWrapper attribute.", verbose: true)
                return
            }
        }

        logger.log("* Found declaration of \(name) (USR: \(usr))")
        dataStore.processedUsrs.insert(usr)

        let receiver: String? = dict[keys.receiver]
        if receiver == nil {
            dataStore.usrRelationDictionary[usr] = dict
        }
    }
}

// MARK: Obfuscating

extension SourceKitObfuscator {
    @discardableResult
    func obfuscate() throws -> ConversionMap {
        try dataStore.indexedFiles.forEach { index in
            try obfuscate(index: index)
        }
        try dataStore.plists.forEach { plist in
            try obfuscate(plist: plist)
        }
        if !dataStore.ibxmls.isEmpty {
            let xmlObfuscationWrapper = IBXMLObfuscationWrapper(obfuscationDictionary: dataStore.obfuscationDictionary, modulesToIgnore: modulesToIgnore)
            try dataStore.ibxmls.forEach { xmlFile in
                try obfuscate(ibxml: xmlFile, xmlObfuscator: xmlObfuscationWrapper)
            }
        }
        return ConversionMap(obfuscationDictionary: dataStore.obfuscationDictionary)
    }

    func obfuscate(index: IndexedFile) throws {
        logger.log("--- Obfuscating \(index.file.name)")
        var referenceArray = [Reference]()
        index.response.recurseEntities { [unowned self] dict in
            guard let kindId: SKUID = dict[keys.kind],
                  kindId.referenceType() != nil || kindId.declarationType() != nil,
                  let rawName: String = dict[keys.name],
                  let usr: String = dict[keys.usr],
                  dataStore.processedUsrs.contains(usr),
                  let line: Int = dict[keys.line],
                  let column: Int = dict[keys.column],
                  dict.isReferencingInternalFramework(dataStore: self.dataStore) == false
            else {
                return
            }

            let name = rawName.removingParameterInformation
            let obfuscatedName = obfuscate(name: name)
            logger.log("* Found reference of \(name) (USR: \(usr) at \(index.file.name) (\(line):\(column)) -> now \(obfuscatedName)")
            let reference = Reference(name: name, line: line, column: column)
            referenceArray.append(reference)
        }
        let originalContents = try index.file.read()
        let obfuscatedContents = obfuscate(fileContents: originalContents, fromReferences: referenceArray)
        if let error = delegate?.obfuscator(self, didObfuscateFile: index.file, newContents: obfuscatedContents) {
            throw error
        }
    }

    func obfuscate(plist: File) throws {
        var data = try plist.read()
        let regex = "\\$\\(PRODUCT_MODULE_NAME\\)\\.[^ \n]*<"
        let results = data.match(regex: regex)
        guard results.isEmpty == false else {
            return
        }
        logger.log("--- Obfuscating \(plist.name)")
        for result in results.reversed() {
            let value = String(result.captureGroup(0, originalString: data).dropLast())
            let range = result.captureGroupRange(0, originalString: data)
            let productModuleName = "$(PRODUCT_MODULE_NAME)"
            let currentName = value.components(separatedBy: "\(productModuleName).").last ?? ""
            let protectedName = dataStore.obfuscationDictionary[currentName] ?? currentName
            let newPlistValue = productModuleName + "." + protectedName + "<"
            data = data.replacingCharacters(in: range, with: newPlistValue)
        }
        let newPlist = data
        if let error = delegate?.obfuscator(self, didObfuscateFile: plist, newContents: newPlist) {
            throw error
        }
    }

    func obfuscate(ibxml: File, xmlObfuscator: IBXMLObfuscationWrapper) throws {
        logger.log("--- Obfuscating \(ibxml.name)")
        let newContents = try xmlObfuscator.obfuscate(file: ibxml)
        if let error = delegate?.obfuscator(self, didObfuscateFile: ibxml, newContents: newContents) {
            throw error
        }
    }

    func obfuscate(name: String) -> String {
        let cachedResult = dataStore.obfuscationDictionary[name]
        guard cachedResult == nil else {
            return cachedResult!
        }
        
        var newName = ""
        switch wordType {
        case .random:
            let size = 32
            let letters: [Character] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
            let numbers: [Character] = Array("0123456789")
            let lettersAndNumbers = letters + numbers
            var randomString = ""
            for i in 0 ..< size {
                let characters: [Character] = i == 0 ? letters : lettersAndNumbers
                let rand = Int.random(in: 0 ..< characters.count)
                let nextChar = characters[rand]
                randomString.append(nextChar)
            }
            newName = randomString
        case .words:
            newName = TypeNameObfuscator.obscure(name: name)
        }

        guard dataStore.obfuscatedNames.contains(newName) == false else {
            return obfuscate(name: name)
        }
        dataStore.obfuscatedNames.insert(newName)
        dataStore.obfuscationDictionary[name] = newName
        return newName
    }

    func obfuscate(fileContents: String, fromReferences references: [Reference]) -> String {
        let sortedReferences = references.sorted(by: <)

        var previousReference: Reference!
        var currentReferenceIndex = 0
        var line = 1
        var column = 1
        var currentCharIndex = 0

        var charArray: [String] = Array(fileContents).map(String.init)

        while currentCharIndex < charArray.count, currentReferenceIndex < sortedReferences.count {
            let reference = sortedReferences[currentReferenceIndex]
            if previousReference != nil,
               reference.line == previousReference.line,
               reference.column == previousReference.column
            {
                // Avoid duplicates.
                currentReferenceIndex += 1
            }
            let currentCharacter = charArray[currentCharIndex]
            if line == reference.line, column == reference.column {
                previousReference = reference
                let originalName = reference.name
                let obfuscatedName = obfuscate(name: originalName)
                let wasInternalKeyword = currentCharacter == "`"
                for i in 1 ..< (originalName.count + (wasInternalKeyword ? 2 : 0)) {
                    charArray[currentCharIndex + i] = ""
                }
                charArray[currentCharIndex] = obfuscatedName
                currentReferenceIndex += 1
                currentCharIndex += originalName.count
                column += originalName.utf8Count
                if wasInternalKeyword {
                    charArray[currentCharIndex] = ""
                }
            } else if currentCharacter == "\n" {
                line += 1
                column = 1
                currentCharIndex += 1
            } else {
                column += currentCharacter.utf8Count
                currentCharIndex += 1
            }
        }
        return charArray.joined()
    }
}

extension SourceKitObfuscator {
    func inheritsFromAnyUSR(_ usr: String, anyOf usrs: Set<String>, inModule module: Module) throws -> Bool {
        let usrsKey = usrs.joined(separator: " ")
        if let cache = dataStore.inheritsFromX[usr, default: [:]][usrsKey] {
            return cache
        }

        func result(_ val: Bool) -> Bool {
            dataStore.inheritsFromX[usr, default: [:]][usrsKey] = val
            return val
        }

        let req = SKRequestDictionary(sourcekitd: sourceKit)
        req[keys.request] = requests.cursorinfo
        req[keys.compilerargs] = module.compilerArguments
        req[keys.usr] = usr
        // We have to store the file of the USR because it looks CursorInfo doesn't returns USRs if you use the wrong one
        // , except if it's a closed source framework. No idea why it works like that.
        // Hopefully this won't break in the future.
        let file: File = dataStore.fileForUSR[usr] ?? module.sourceFiles.first!
        req[keys.sourcefile] = file.path
        let cursorInfo = try sourceKit.sendSync(req)
        guard let annotation: String = cursorInfo[keys.annotated_decl] else {
            logger.log("Pretending \(usr) inherits from Codable because SourceKit failed to look it up. This can happen if this USR belongs to an @objc class.", verbose: true)
            return result(true)
        }
        let regex = "usr=\\\"(.\\S*)\\\""
        let regexResult = annotation.match(regex: regex)
        for res in regexResult {
            let inheritedUSR = res.captureGroup(1, originalString: annotation)
            if usrs.contains(inheritedUSR) {
                return result(true)
            } else if try inheritsFromAnyUSR(inheritedUSR, anyOf: usrs, inModule: module) {
                return result(true)
            }
        }
        return result(false)
    }
}

// MARK: SKResponseDictionary Helpers

extension SKResponseDictionary {
    var isPublic: Bool {
        if let kindId: SKUID = self[sourcekitd.keys.kind], let type = kindId.declarationType(), type == .enumelement {
            return parent.isPublic
        }
        guard let attributes: SKResponseArray = self[sourcekitd.keys.attributes] else {
            return false
        }
        guard attributes.count > 0 else {
            return false
        }
        for i in 0 ..< attributes.count {
            guard let attr: SKUID = attributes[i][sourcekitd.keys.attribute] else {
                continue
            }
            guard attr.asString == AccessControl.public.rawValue || attr.asString == AccessControl.open.rawValue else {
                continue
            }
            return true
        }
        return false
    }

    func isReferencingInternalFramework(dataStore: SourceKitObfuscatorDataStore) -> Bool {
        guard let kindId: SKUID = self[sourcekitd.keys.kind] else {
            return false
        }
        let type = kindId.referenceType() ?? kindId.declarationType()
        guard type == .method || type == .property else {
            return false
        }
        guard let usr: String = self[sourcekitd.keys.usr] else {
            return false
        }
        let usrRelationDict = dataStore.usrRelationDictionary
        if let dict: SKResponseDictionary = usrRelationDict[usr], self.dict.data != dict.dict.data {
            return dict.isReferencingInternalFramework(dataStore: dataStore)
        }
        var isReference = false
        recurse(uid: sourcekitd.keys.related) { [unowned self] dict in
            guard isReference == false else {
                return
            }
            guard let usr: String = dict[sourcekitd.keys.usr] else {
                return
            }
            if dataStore.processedUsrs.contains(usr) == false {
                isReference = true
            } else if let dict: SKResponseDictionary = usrRelationDict[usr] {
                isReference = dict.isReferencingInternalFramework(dataStore: dataStore)
            }
        }
        return isReference
    }
}
