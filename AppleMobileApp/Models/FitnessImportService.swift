import Foundation

#if os(iOS)
import HealthKit

enum FitnessImportService {
    private static let store = HKHealthStore()

    static func importRecentEntries(days: Int = 7) async throws -> [LogEntry] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw FitnessImportError.healthDataUnavailable
        }

        let workoutType = HKObjectType.workoutType()
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw FitnessImportError.healthDataUnavailable
        }

        try await store.requestAuthorization(toShare: [], read: [workoutType, sleepType])

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        async let workouts = samples(of: workoutType, since: startDate)
        async let sleep = samples(of: sleepType, since: startDate)
        let imported = try await workoutEntries(from: workouts) + sleepEntries(from: sleep)
        return imported.sorted { $0.timestamp > $1.timestamp }
    }

    private static func samples(of type: HKSampleType, since startDate: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    private static func workoutEntries(from samples: [HKSample]) -> [LogEntry] {
        samples.compactMap { sample in
            guard let workout = sample as? HKWorkout else { return nil }
            return LogEntry(
                timestamp: workout.startDate,
                category: .fitness,
                title: workoutTitle(for: workout.workoutActivityType),
                note: "Imported from Apple Health",
                durationMinutes: max(1, Int(workout.duration / 60)),
                lifeArea: .personal,
                deviceSource: .offline,
                fitnessSource: workout.sourceRevision.source.name,
                externalIdentifier: "health-workout-\(workout.uuid.uuidString)"
            )
        }
    }

    private static func sleepEntries(from samples: [HKSample]) -> [LogEntry] {
        samples.compactMap { sample in
            guard let sleep = sample as? HKCategorySample,
                  sleep.value != HKCategoryValueSleepAnalysis.inBed.rawValue,
                  sleep.value != HKCategoryValueSleepAnalysis.awake.rawValue else { return nil }

            return LogEntry(
                timestamp: sleep.startDate,
                category: .sleep,
                title: "Sleep",
                note: "Imported from Apple Health",
                durationMinutes: max(1, Int(sleep.endDate.timeIntervalSince(sleep.startDate) / 60)),
                lifeArea: .rest,
                deviceSource: .offline,
                fitnessSource: sleep.sourceRevision.source.name,
                externalIdentifier: "health-sleep-\(sleep.uuid.uuidString)"
            )
        }
    }

    private static func workoutTitle(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycling"
        case .swimming: "Swim"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength training"
        case .highIntensityIntervalTraining: "HIIT workout"
        case .hiking: "Hike"
        case .mindAndBody: "Mind and body session"
        default: "Workout"
        }
    }
}

#else

enum FitnessImportService {
    static func importRecentEntries(days: Int = 7) async throws -> [LogEntry] {
        throw FitnessImportError.mobileDeviceRequired
    }
}

#endif

enum FitnessImportError: LocalizedError {
    case healthDataUnavailable
    case mobileDeviceRequired

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "Apple Health data is not available on this device."
        case .mobileDeviceRequired:
            "Connect Apple Health from Sakhya on your iPhone or iPad."
        }
    }
}
