import Foundation

enum SampleDataFactory {
    static func make(days: Int, lists: [SakhyaList], now: Date = .now) -> [LogEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let groceries = lists.first { $0.kind == .grocery }?.id
        let shopping = lists.first { $0.kind == .shopping }?.id
        let reminders = lists.first { $0.kind == .reminder }?.id
        let tasks = lists.first { $0.kind == .task }?.id
        let foods = ["Oats, berries and coffee", "Vegetable curry and rice", "Pasta with tomato and basil", "Greek yogurt and fruit", "Dal, roti and salad"]
        let expenses: [(String, Double)] = [("Groceries", 34.80), ("Lunch", 12.40), ("Coffee", 4.20), ("Train ticket", 18.60), ("Household supplies", 27.90)]
        let workouts = ["Outdoor walk", "Strength workout", "Easy run", "Yoga session", "Cycling"]
        let moods = ["Calm and focused", "Energetic morning", "A little tired, still optimistic", "Grateful for a balanced day", "Clear-headed after a walk"]
        let books = ["Atomic Habits", "The Psychology of Money", "Deep Work", "Sapiens"]
        let movies = ["The Lunchbox", "Arrival", "Perfect Days", "The Social Network"]
        var output: [LogEntry] = []

        func date(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        for offset in 0..<max(days, 1) {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let variant = (offset * 7 + 3) % 5
            let sleep = 405 + ((offset * 17) % 75)
            let work = calendar.isDateInWeekend(day) ? 45 : 330 + ((offset * 13) % 90)
            let screen = 70 + ((offset * 23) % 105)
            let active = 25 + ((offset * 11) % 45)

            output += [
                LogEntry(timestamp: date(day, 6, 45 + variant * 4), category: .sleep, title: "Slept \(sleep / 60)h \(sleep % 60)m", durationMinutes: sleep, lifeArea: .rest, deviceSource: .phone, fitnessSource: "Apple Health", externalIdentifier: "sample-sleep-\(offset)", isSampleData: true),
                LogEntry(timestamp: date(day, 7, 30), category: .routine, title: "Morning routine and water", note: "Started without checking notifications", durationMinutes: 25, lifeArea: .personal, deviceSource: .offline, isSampleData: true),
                LogEntry(timestamp: date(day, 8, 10), category: .food, title: foods[variant], lifeArea: .personal, deviceSource: .phone, isSampleData: true),
                LogEntry(timestamp: date(day, 9, 5), category: .work, title: calendar.isDateInWeekend(day) ? "Weekly planning" : "Focused work block", note: "Protected time for the main priority", durationMinutes: work, lifeArea: .work, deviceSource: .mac, isSampleData: true),
                LogEntry(timestamp: date(day, 13, 5), category: .expense, title: expenses[variant].0, amount: expenses[variant].1 + Double(offset % 3), lifeArea: .personal, deviceSource: .phone, isSampleData: true),
                LogEntry(timestamp: date(day, 18, 15), category: .fitness, title: workouts[variant], note: "Imported from Apple Health", durationMinutes: active, lifeArea: .personal, deviceSource: .phone, fitnessSource: variant == 1 ? "WHOOP" : "Apple Watch", externalIdentifier: "sample-workout-\(offset)", isSampleData: true),
                LogEntry(timestamp: date(day, 20, 20), category: .screenTime, title: "Daily screen time", durationMinutes: screen, lifeArea: .personal, deviceSource: .phone, externalIdentifier: "sample-screen-\(offset)", isSampleData: true),
                LogEntry(timestamp: date(day, 21, 15), category: .mood, title: moods[variant], mood: 3 + (offset % 3), lifeArea: .personal, deviceSource: .phone, isSampleData: true),
                LogEntry(timestamp: date(day, 21, 40), category: .journal, title: "Daily reflection", note: "I moved the important things forward and made space to recharge. Tomorrow I want to begin with one clear priority.", lifeArea: .personal, deviceSource: .mac, isSampleData: true)
            ]

            if offset % 4 == 0 {
                output.append(LogEntry(timestamp: date(day, 19, 35), category: .book, title: "Read \(books[(offset / 4) % books.count])", durationMinutes: 30, status: offset == 0 ? .inProgress : .completed, lifeArea: .personal, deviceSource: .tablet, isSampleData: true))
            }
            if offset % 6 == 0 {
                output.append(LogEntry(timestamp: date(day, 20, 45), category: .movie, title: offset == 0 ? "Want to watch \(movies[0])" : "Watched \(movies[(offset / 6) % movies.count])", status: offset == 0 ? .planned : .completed, lifeArea: .personal, deviceSource: .tablet, isSampleData: true))
            }
        }

        let due = calendar.date(byAdding: .hour, value: 3, to: now)
        output += [
            LogEntry(timestamp: now, category: .list, title: "Milk, spinach and bananas", listKind: .grocery, listID: groceries, isSampleData: true),
            LogEntry(timestamp: now.addingTimeInterval(-60), category: .list, title: "New running shoes", listKind: .shopping, listID: shopping, isSampleData: true),
            LogEntry(timestamp: now.addingTimeInterval(-120), category: .list, title: "Call the dentist", listKind: .reminder, listID: reminders, dueDate: due, isSampleData: true),
            LogEntry(timestamp: now.addingTimeInterval(-180), category: .list, title: "Plan the week", listKind: .task, listID: tasks, isSampleData: true)
        ]
        return output.sorted { $0.timestamp > $1.timestamp }
    }
}
