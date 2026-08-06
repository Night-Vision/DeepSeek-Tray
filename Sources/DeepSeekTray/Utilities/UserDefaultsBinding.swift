import SwiftUI

extension UserDefaults {
    func stringBinding(forKey key: String, default defaultValue: String = "") -> Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: key) ?? defaultValue },
            set: { UserDefaults.standard.set($0, forKey: key) }
        )
    }
}
