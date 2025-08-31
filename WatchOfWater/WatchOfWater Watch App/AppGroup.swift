import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum AppGroup {
    // TODO: Set your App Group identifier in Xcode capabilities and here.
    static let id = "group.watchofwater"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }

    static func sync(water: Double? = nil, goal: Double? = nil) {
        guard let ud = defaults else { return }
        if let w = water { ud.set(w, forKey: "waterIntakeMl") }
        if let g = goal { ud.set(g, forKey: "dailyGoalMl") }
        ud.synchronize()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
