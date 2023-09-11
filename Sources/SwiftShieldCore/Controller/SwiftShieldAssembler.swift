import Foundation

public enum SwiftSwiftAssembler {
    public static func generate(
        projectPath: String,
        scheme: String,
        sdk: String?,
        wordType: String?,
        modulesToIgnore: Set<String>,
        namesToIgnore: Set<String>,
        fileNamesToIgnore: Set<String>,
        excludeTypes: Set<String>,
        ignorePublic: Bool,
        includeIBXMLs: Bool,
        dryRun: Bool,
        verbose: Bool,
        printSourceKitQueries: Bool
    ) -> SwiftShieldController {
        let logger = Logger(
            verbose: verbose,
            printSourceKit: printSourceKitQueries
        )

        let projectFile = File(path: projectPath)
        let taskRunner = TaskRunner()
        let infoProvider = SchemeInfoProvider(
            projectFile: projectFile,
            schemeName: scheme,
            sdk: sdk,
            taskRunner: taskRunner,
            logger: logger,
            modulesToIgnore: modulesToIgnore,
            includeIBXMLs: includeIBXMLs
        )

        let dataStore = SourceKitObfuscatorDataStore()
        dataStore.readCache()
        let sourceKit = SourceKit(logger: logger)
        let obfuscator = SourceKitObfuscator(
            sourceKit: sourceKit,
            logger: logger,
            dataStore: dataStore,
            namesToIgnore: namesToIgnore,
            ignorePublic: ignorePublic,
            wordType: wordType,
            modulesToIgnore: modulesToIgnore,
            fileNamesToIgnore: fileNamesToIgnore,
            excludeTypes: excludeTypes
        )

        let interactor = SwiftShieldInteractor(
            schemeInfoProvider: infoProvider,
            logger: logger,
            obfuscator: obfuscator
        )
        
        

        return SwiftShieldController(
            interactor: interactor,
            dataStore: dataStore,
            logger: logger,
            dryRun: dryRun
        )
    }
}
