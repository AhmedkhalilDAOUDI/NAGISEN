import Foundation
import Security

struct DaywellWidgetSnapshot: Codable {
    static let groupID = "QUC3ZC876T.com.daywell.nutrition.shared"
    static let storageKey = "daywell.widget.snapshot.v1"

    var date: Date
    var calories: Int
    var calorieGoal: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var water: Int
    var waterGoal: Int
    var steps: Int?
    var moveCalories: Int?
    var moveGoalCalories: Int?
    var distanceKilometers: Double?
    var weekCalories: [Int?]

    static var empty: Self {
        .init(date: .now, calories: 0, calorieGoal: 2000, protein: 0,
              carbs: 0, fat: 0, water: 0, waterGoal: 2500,
              steps: nil, moveCalories: nil, moveGoalCalories: nil, distanceKilometers: nil,
              weekCalories: Array(repeating: nil, count: 7))
    }

    static func load() -> Self {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: storageKey,
            kSecAttrAccount as String: "current",
            kSecAttrAccessGroup as String: groupID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        guard Calendar.current.isDateInToday(snapshot.date) else {
            var fresh = snapshot
            fresh.date = .now
            fresh.calories = 0
            fresh.protein = 0
            fresh.carbs = 0
            fresh.fat = 0
            fresh.water = 0
            fresh.steps = nil
            fresh.moveCalories = nil
            fresh.moveGoalCalories = nil
            fresh.distanceKilometers = nil
            return fresh
        }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.storageKey,
            kSecAttrAccount as String: "current",
            kSecAttrAccessGroup as String: Self.groupID
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
