import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

enum HealthServiceError: Error {
    case notAvailable
    case unauthorized
}

final class HealthService {
    static let shared = HealthService()
    private init() {}

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        #if canImport(HealthKit)
        guard isAvailable else { completion(false, HealthServiceError.notAvailable); return }
        var readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!
        ]
        // Optional reads for reminders personalization
        if let sc = HKObjectType.quantityType(forIdentifier: .stepCount) { readTypes.insert(sc) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { readTypes.insert(sleep) }
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!
        ]
        store.requestAuthorization(toShare: writeTypes, read: readTypes) { granted, error in
            DispatchQueue.main.async { completion(granted, error) }
        }
        #else
        completion(false, HealthServiceError.notAvailable)
        #endif
    }

    // MARK: - Read latest metrics
    #if canImport(HealthKit)
    private func fetchLatestQuantity(for id: HKQuantityTypeIdentifier,
                                     unit: HKUnit,
                                     completion: @escaping (Double?) -> Void) {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { completion(nil); return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let self = self else { completion(nil); return }
            guard let q = samples?.first as? HKQuantitySample else { DispatchQueue.main.async { completion(nil) }; return }
            let value = q.quantity.doubleValue(for: unit)
            DispatchQueue.main.async { completion(value) }
        }
        store.execute(query)
    }

    func fetchBodyMassKg(completion: @escaping (Double?) -> Void) {
        fetchLatestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo), completion: completion)
    }

    func fetchHeightMeters(completion: @escaping (Double?) -> Void) {
        fetchLatestQuantity(for: .height, unit: .meter(), completion: completion)
    }
    #endif

    // MARK: - Recommended goal
    // Basic heuristic: 35 ml/kg adjusted slightly by height.
    func recommendedDailyGoalMl(weightKg: Double?, heightMeters: Double?) -> Double {
        let w = max(0, weightKg ?? 0)
        var ml = w * 35.0
        if let h = heightMeters {
            let cm = h * 100.0
            if cm >= 185 { ml += 250 }
            else if cm <= 160 { ml -= 150 }
        }
        ml = max(1500, min(ml, 4000))
        return round(ml / 50.0) * 50.0 // round to nearest 50 ml
    }

    // Convenience to compute from Health data
    func computeRecommendedFromHealth(completion: @escaping (Double?) -> Void) {
        #if canImport(HealthKit)
        fetchBodyMassKg { [weak self] kg in
            guard let self = self else { completion(nil); return }
            self.fetchHeightMeters { m in
                let goal = self.recommendedDailyGoalMl(weightKg: kg, heightMeters: m)
                completion(goal)
            }
        }
        #else
        completion(nil)
        #endif
    }

    // MARK: - Sleep window (heuristic)
    func fetchTodayWakingWindow(completion: @escaping ((Int, Int)?) -> Void) {
        #if canImport(HealthKit)
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { completion(nil); return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: cal.date(byAdding: .day, value: -1, to: startOfDay), end: cal.date(byAdding: .day, value: 1, to: startOfDay), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let cat = samples as? [HKCategorySample] ?? []
            // Find the last sleep segment that ends after today's midnight (wake-up time)
            var wakeStart = startOfDay
            for s in cat {
                if s.endDate >= startOfDay && s.value != 0 { // asleep/inBed categories are non-zero
                    if s.endDate > wakeStart { wakeStart = s.endDate }
                }
            }
            // Heuristic: waking window 16 hours after wakeStart (capped at 23:30)
            let end = min(wakeStart.addingTimeInterval(16*3600), cal.date(bySettingHour: 23, minute: 30, second: 0, of: wakeStart) ?? wakeStart.addingTimeInterval(16*3600))
            let m1 = cal.component(.hour, from: wakeStart) * 60 + cal.component(.minute, from: wakeStart)
            let m2 = cal.component(.hour, from: end) * 60 + cal.component(.minute, from: end)
            DispatchQueue.main.async { completion((m1, m2)) }
        }
        store.execute(query)
        #else
        completion(nil)
        #endif
    }

    // MARK: - Activity weights (steps per hour average)
    func fetchHourlyStepsAverage(days: Int = 7, completion: @escaping ([Double]?) -> Void) {
        #if canImport(HealthKit)
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { completion(nil); return }
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { completion(nil); return }
        var interval = DateComponents()
        interval.hour = 1
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: cal.startOfDay(for: start), intervalComponents: interval)
        query.initialResultsHandler = { _, collection, _ in
            var sums = Array(repeating: 0.0, count: 24)
            var counts = Array(repeating: 0, count: 24)
            collection?.enumerateStatistics(from: start, to: end, with: { stats, _ in
                let hour = cal.component(.hour, from: stats.startDate)
                if let q = stats.sumQuantity() {
                    sums[hour] += q.doubleValue(for: HKUnit.count())
                    counts[hour] += 1
                }
            })
            var avg = [Double]()
            for i in 0..<24 {
                avg.append(counts[i] > 0 ? sums[i] / Double(max(1, counts[i])) : 0)
            }
            let maxv = avg.max() ?? 0
            let norm = maxv > 0 ? avg.map { $0 / maxv } : Array(repeating: 1.0, count: 24)
            DispatchQueue.main.async { completion(norm) }
        }
        store.execute(query)
        #else
        completion(nil)
        #endif
    }

    // MARK: - Save water intake
    func saveWaterIntake(ml: Double, at date: Date = Date(), completion: ((Bool, Error?) -> Void)? = nil) {
        #if canImport(HealthKit)
        guard isAvailable else { completion?(false, HealthServiceError.notAvailable); return }
        guard let type = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { completion?(false, HealthServiceError.unauthorized); return }
        let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        store.save(sample) { success, error in
            DispatchQueue.main.async { completion?(success, error) }
        }
        #else
        completion?(false, HealthServiceError.notAvailable)
        #endif
    }

    // MARK: - Today total (optional)
    func fetchTodayWaterTotalMl(completion: @escaping (Double?) -> Void) {
        #if canImport(HealthKit)
        guard let type = HKObjectType.quantityType(forIdentifier: .dietaryWater) else { completion(nil); return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var comps = DateComponents(); comps.day = 1; comps.second = -1
        let end = cal.date(byAdding: comps, to: start) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
            let value = stats?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli))
            DispatchQueue.main.async { completion(value) }
        }
        store.execute(query)
        #else
        completion(nil)
        #endif
    }
}
