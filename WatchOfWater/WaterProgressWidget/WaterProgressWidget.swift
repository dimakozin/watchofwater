//
//  WaterProgressWidget.swift
//  WatchOfWater
//
//  Created by Дмитрий Козин on 31.08.2025.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared reader for App Group data
enum SharedWaterStore {
    static let groupID = "group.watchofwater"
    static func read() -> (water: Double, goal: Double, progress: Double) {
        let ud = UserDefaults(suiteName: groupID)
        let water = ud?.double(forKey: "waterIntakeMl") ?? 0
        let goal = max(ud?.double(forKey: "dailyGoalMl") ?? 2000, 1)
        let progress = min(max(water / goal, 0), 1)
        return (water, goal, progress)
    }
}

// MARK: - Timeline
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let now = Date()
        let entry = SimpleEntry(date: now, configuration: configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(next))
    }

    func recommendations() -> [AppIntentRecommendation<ConfigurationAppIntent>] {
        [AppIntentRecommendation(intent: ConfigurationAppIntent(),
                                 description: "Процент воды (от суточной нормы)")]
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
}

// MARK: - Widget
@main
struct WaterProgressWidget: Widget {
    let kind: String = "WaterProgressWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: ConfigurationAppIntent.self,
                               provider: Provider()) { entry in
            WaterProgressWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Вода")
        .description("Прогресс приема воды за сутки.")
        .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - View
struct WaterProgressWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        let data = SharedWaterStore.read()
        AccessoryView(progress: data.progress, water: data.water, goal: data.goal)
    }
}

struct AccessoryView: View {
    let progress: Double
    let water: Double
    let goal: Double

    @Environment(\.widgetFamily) private var family

    var body: some View {
        let pct = Int((progress * 100).rounded())

        switch family {
        // === УГЛОВАЯ: капля и процент (система изгибает текст по дуге)
        case .accessoryCorner:
            ZStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .opacity(0.95)
                    .offset(x: -4, y: 2)
            }
            .widgetLabel {
                Text("\(pct)%").monospacedDigit()
            }

        // === КРУГЛАЯ: капля по центру + процент
        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("\(pct)%")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }

        // === ПРЯМОУГОЛЬНАЯ: капля слева, процент справа
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("\(pct)%")
                    .font(.caption2)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }

        // === Фолбэк
        default:
            HStack(spacing: 6) {
                Image(systemName: "drop.fill").foregroundStyle(.tint)
                Text("\(pct)%").monospacedDigit()
            }
        }
    }
}

// MARK: - Helpers & Previews
private extension Double {
    func clip() -> CGFloat { CGFloat(min(max(self, 0), 1)) }
}

extension ConfigurationAppIntent {
    fileprivate static var sample: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "💧"
        return intent
    }
}

#Preview(as: .accessoryCorner) {
    WaterProgressWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: .sample)
}
