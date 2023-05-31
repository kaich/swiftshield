import DifferentModule
import UIKit
import CoreData

func globalMethod() {}
var globalProp = 0

struct SomeStruct {
    static func staticMethod() {}
    func method() {}
    static let singleton = SomeStruct()
    var instanceProp = 0
}

enum SomeEnum {
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
        StructFromDifferentModule.methodFromDifferentModule()
        
        
    }

    func method(_: SomeEnum) {
        globalMethod()
    }

    func anotherMethod() {
        method(SomeEnum.a)
        method(SomeEnum.b)
        method(SomeEnum.c)
        globalMethod()
    }
}

class DataManager {
    static let shared = DataManager()

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

extension DataManager {
    func creatingContact() {
        let contact = TestEntity(context: persistentContainer.viewContext)
        contact.testAttribute = "test"
    }
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get {
            return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
        }
        set {
            if let optional = newValue as? AnyOptional, optional.isNil {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(newValue, forKey: key)
            }
        }
    }
}
