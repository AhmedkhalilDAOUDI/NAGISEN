import Foundation
import UserNotifications

/// Streak reminders and border nudges, scheduled on the phone (no server needed).
/// Rescheduled whenever the app opens or the diary changes, so they never fire after
/// the day is already checked off.
enum Reminders {
    static let streakKey = "nagisen.reminders.streak"
    static let streakHourKey = "nagisen.reminders.streakHour"
    static let streakMinuteKey = "nagisen.reminders.streakMinute"
    static let borderKey = "nagisen.reminders.border"
    private static let lastNudgedKey = "nagisen.reminders.lastNudgedTier"
    private static let streakDays = 3
    private static let streakIDs = (0..<streakDays).map { "nagisen.streak.\($0)" }
    private static let borderID = "nagisen.border.nudge"
    /// Within this many points of the next border, a nudge is worth sending.
    static let nudgeWithin = 5

    static var defaultStreakTime: (hour: Int, minute: Int) { (20, 30) }

    // MARK: - Decisions (pure, tested)

    /// The evenings to remind on: today (if not checked and the time hasn't passed) and the
    /// following days, so a reminder still comes if the app isn't opened for a while.
    static func streakReminderDates(now: Date, todayChecked: Bool, hour: Int, minute: Int,
                                    days: Int = streakDays, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            if offset == 0 && (todayChecked || time <= now) { return nil }
            return time
        }
    }

    /// The border to nudge about: the next one, when it is close and hasn't been nudged yet.
    static func borderToNudge(_ progress: PathProgress, lastNudged: Int?) -> BorderTier? {
        guard let next = progress.tier.next, let needed = progress.pointsToNext,
              needed > 0, needed <= nudgeWithin, next.rawValue != lastNudged else { return nil }
        return next
    }

    // MARK: - Scheduling

    @MainActor
    static func reconcile(store: NutritionStore) {
        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: streakIDs)
        let streakOn = defaults.bool(forKey: streakKey)
        let borderOn = defaults.bool(forKey: borderKey)
        guard streakOn || borderOn else { return }

        let now = Date()
        let hour = defaults.object(forKey: streakHourKey) as? Int ?? defaultStreakTime.hour
        let minute = defaults.object(forKey: streakMinuteKey) as? Int ?? defaultStreakTime.minute
        let dates = streakOn ? streakReminderDates(now: now, todayChecked: store.isLoggingComplete(on: now),
                                                   hour: hour, minute: minute) : []
        let streak = store.streakSnapshot(asOf: now).activeStreak
        let progress = PathProgress(store: store)
        let nudge = borderOn ? borderToNudge(progress, lastNudged: defaults.object(forKey: lastNudgedKey) as? Int) : nil

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let center = UNUserNotificationCenter.current()
            for (index, date) in dates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "NAGISEN"
                content.body = streak > 0
                    ? "Your \(streak)-day streak is waiting. Check off today when you're done logging."
                    : "Log your day and check it off to start a streak."
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                center.add(UNNotificationRequest(identifier: streakIDs[index], content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
            if let nudge, let needed = progress.pointsToNext {
                let content = UNMutableNotificationContent()
                content.title = "Almost \(nudge.name)"
                content.body = "\(needed) \(needed == 1 ? "point" : "points") to your \(nudge.name) border."
                content.sound = .default
                let evening = streakReminderDates(now: now, todayChecked: false, hour: 19, minute: 0, days: 2).first ?? now
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: evening)
                center.add(UNNotificationRequest(identifier: borderID, content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                DispatchQueue.main.async { UserDefaults.standard.set(nudge.rawValue, forKey: lastNudgedKey) }
            }
        }
    }

    /// Asks for permission the first time a reminder is turned on.
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func cancelBorderNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [borderID])
    }
}
