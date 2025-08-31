import Foundation
import UserNotifications
#if canImport(HealthKit)
import HealthKit
#endif

struct ReminderConfig: Codable {
    var enabled: Bool
    var count: Int
    var startMinutes: Int // minutes from midnight
    var endMinutes: Int   // minutes from midnight
}

enum ReminderService {
    private static let idPrefix = "water.reminder."

    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion?(true)
            case .denied:
                completion?(false)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    completion?(granted)
                }
            @unknown default:
                completion?(false)
            }
        }
    }

    static func cancelScheduled() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map { $0.identifier }.filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    static func schedule(config: ReminderConfig,
                         personalized: Bool = false,
                         autoWaking: Bool = false,
                         completion: ((Bool) -> Void)? = nil) {
        guard config.enabled, config.count > 0 else {
            cancelScheduled()
            completion?(true)
            return
        }
        requestAuthorization { granted in
            guard granted else { completion?(false); return }
            cancelScheduled()

            func actuallySchedule(start: Int, end: Int, weights: [Double]?) {
                let center = UNUserNotificationCenter.current()
                let s = max(0, min(24*60-1, start))
                let e = max(0, min(24*60, end))
                guard e > s else { completion?(false); return }

                var times: [Int] = []
                if let w = weights, personalized {
                    // Pick hours within window, prioritize by weight
                    var hourWeights: [(Int, Double)] = []
                    let sh = s/60, eh = max(sh, (e-1)/60)
                    for h in sh...eh { hourWeights.append((h, w[h])) }
                    hourWeights.sort { $0.1 > $1.1 }
                    var chosen: Set<Int> = []
                    for (h, _) in hourWeights {
                        times.append(h*60 + 30) // middle of hour
                        chosen.insert(h)
                        if times.count >= config.count { break }
                    }
                    if times.count < config.count {
                        // Fill remaining evenly
                        let span = e - s
                        let step = max(1, span / (config.count + 1))
                        for i in 1...config.count where times.count < config.count {
                            times.append(s + i*step)
                        }
                    }
                } else {
                    let span = e - s
                    let step = max(1, span / (config.count + 1))
                    for i in 1...config.count { times.append(s + i*step) }
                }

                for (idx, minutes) in times.enumerated() {
                    var comps = DateComponents()
                    comps.hour = minutes / 60
                    comps.minute = minutes % 60
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                    let content = UNMutableNotificationContent()
                    content.title = "Пора выпить воды"
                    content.body = "Небольшой глоток поможет держать темп дня"
                    content.sound = .default
                    let id = idPrefix + String(idx+1)
                    let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                    center.add(req, withCompletionHandler: nil)
                }
                completion?(true)
            }

            if autoWaking {
                HealthService.shared.fetchTodayWakingWindow { win in
                    let window = win ?? (config.startMinutes, config.endMinutes)
                    if personalized {
                        HealthService.shared.fetchHourlyStepsAverage { weights in
                            actuallySchedule(start: window.0, end: window.1, weights: weights)
                        }
                    } else {
                        actuallySchedule(start: window.0, end: window.1, weights: nil)
                    }
                }
            } else {
                if personalized {
                    HealthService.shared.fetchHourlyStepsAverage { weights in
                        actuallySchedule(start: config.startMinutes, end: config.endMinutes, weights: weights)
                    }
                } else {
                    actuallySchedule(start: config.startMinutes, end: config.endMinutes, weights: nil)
                }
            }
        }
    }

    #if DEBUG
    static func sendTestNotification() {
        requestAuthorization { granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Тест воды"
            content.body = "Это тестовое напоминание"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            let req = UNNotificationRequest(identifier: idPrefix+"test", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
    }
    #endif
}
