#if canImport(WidgetKit)
import WidgetKit
import SwiftUI

@available(watchOS 7.0, *)
struct WaterProgressEntry: TimelineEntry {
    let date: Date
    let progress: Double
}

@available(watchOS 7.0, *)
struct WaterProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterProgressEntry {
        WaterProgressEntry(date: Date(), progress: 0.6)
    }
    func getSnapshot(in context: Context, completion: @escaping (WaterProgressEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterProgressEntry>) -> Void) {
        let entry = currentEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func currentEntry() -> WaterProgressEntry {
        let ud = UserDefaults.standard
        let water = ud.double(forKey: "waterIntakeMl")
        let goal = max(ud.double(forKey: "dailyGoalMl"), 1)
        let prog = min(max(water / goal, 0), 1)
        return WaterProgressEntry(date: Date(), progress: prog)
    }
}

@available(watchOS 7.0, *)
struct WaterProgressView: View {
    var entry: WaterProgressEntry
    var body: some View {
        ZStack {
            Circle().stroke(Color.blue.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(entry.progress))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(6)
    }
}

// Для активации: добавьте в проект Widget Extension и используйте эти типы:
// struct WaterProgressWidget: Widget { ... } c использованием WaterProgressProvider и WaterProgressView

#endif

