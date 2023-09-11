import Foundation

final class SourceKitObfuscatorDataStore {
    var processedUsrs = Set<String>()
    var obfuscationDictionary = [String: String]()
    var obfuscatedNames = Set<String>()
    var usrRelationDictionary = [String: SKResponseDictionary]()
    var indexedFiles = [IndexedFile]()
    var plists = Set<File>()
    var ibxmls = Set<File>()
    var inheritsFromX = [String: [String: Bool]]()
    var fileForUSR = [String: File]()
}

extension SourceKitObfuscatorDataStore {
    static let kCacheUrl = FileManager.default.currentDirectoryPath.appending("/.ssdcache")
    
    func saveCache() {
        let url = URL(fileURLWithPath: Self.kCacheUrl)
        do {
            let data = try JSONSerialization.data(withJSONObject: obfuscationDictionary)
            try data.write(to: url)
        } catch {
            Logger().log("Cache obfuscation dictionary failed")
        }
    }
    
    func readCache() {
        let url = URL(fileURLWithPath: Self.kCacheUrl)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                if let dic = try JSONSerialization.jsonObject(with: data) as? [String : String] {
                    self.obfuscationDictionary = dic
                }
            }
        } catch {
            Logger().log("Read obfuscation dictionary cache failed")
        }
    }
    
}
