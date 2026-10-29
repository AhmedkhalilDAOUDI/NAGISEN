import Foundation
import WidgetKit

enum WidgetSync {
    private static var pending: DispatchWorkItem?

    static func schedule(store: NutritionStore, health: HealthManager) {
        pending?.cancel()
        let work = DispatchWorkItem { update(store: store, health: health) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func update(store: NutritionStore, health: HealthManager) {
        let today = Date.now
        let totals = store.totals(on: today)
        let days = (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
        let week = days.map { day -> Int? in
            store.entries(on: day).isEmpty ? nil : store.totals(on: day).calories
        }
        let snapshot = DaywellWidgetSnapshot(date: today, calories: totals.calories,
                                            calorieGoal: store.goals(on: today).calories,
                                            protein: Int(totals.protein.rounded()),
                                            carbs: Int(totals.carbs.rounded()),
                                            fat: Int(totals.fat.rounded()),
                                            water: store.waterTotal(on: today),
                                            waterGoal: store.waterGoalML,
                                            steps: health.steps,
                                            moveCalories: health.activeCalories,
                                            moveGoalCalories: health.moveGoalCalories,
                                            distanceKilometers: health.distanceKilometers,
                                            weekCalories: week)
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
