import DifferentModule
import UIKit
import CoreData

func globalMethod() {}
var globalProp = 0

struct AccusantiumStruct {
    static func staticMethod() {}
    func method() {}
    static let singleton = AccusantiumStruct()
    var instanceProp = 0
}

enum EligendiEnum {
    case a
    case b
    case c

    var bla: String {
        switch self {
        case .a:
            break
        case .b:
            break
        case .c:
            break
        }
        return ""
    }
}

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .green
        QuosRepellendusFacereModule.methodFromDifferentModule()
        
        
    }

    func method(_: EligendiEnum) {
        globalMethod()
    }

    func anotherMethod() {
        method(EligendiEnum.a)
        method(EligendiEnum.b)
        method(EligendiEnum.c)
        globalMethod()
    }
}

class ProvidentManager {
    static let shared = ProvidentManager()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Model")
        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    // Core Data Saving support
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}

extension ProvidentManager {
    func creatingContact() {
        let contact = TestEntity(context: persistentContainer.viewContext)
        contact.testAttribute = "test"
    }
}

@propertyWrapper
struct DoloremqueDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get {
            return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
