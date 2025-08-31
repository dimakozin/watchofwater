import SwiftUI
import UserNotifications
#if canImport(HealthKit)
import HealthKit
#endif

struct SettingsView: View {
    @AppStorage("dailyGoalMl") private var dailyGoalMl: Double = 2000
    @AppStorage("quickAddStepMl") private var quickAddStepMl: Double = 200
    @AppStorage("waterIntakeMl") private var waterIntakeMl: Double = 0
    @AppStorage("softAnimations") private var softAnimations: Bool = false
    @AppStorage("autoHealthGoal") private var autoHealthGoal: Bool = false
    // Напоминания вынесены на отдельный экран
    @AppStorage("remindersAutoWake") private var remindersAutoWake: Bool = true
    @AppStorage("remindersPersonalized") private var remindersPersonalized: Bool = false
    @State private var recommendedGoalMl: Double? = nil
    @State private var todayHealthMl: Double? = nil
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Цель воды") {
                Stepper(value: $dailyGoalMl, in: 500...5000, step: 100) {
                    Text("\(Int(dailyGoalMl)) мл/день").font(.caption2)
                }
            }

            Section("Быстрое добавление") {
                Stepper(value: $quickAddStepMl, in: 50...500, step: 50) {
                    Text("Шаг: \(Int(quickAddStepMl)) мл").font(.caption2)
                }
            }

            #if canImport(HealthKit)
            Section("Здоровье") {
                Toggle("Автоматическая цель по Health", isOn: $autoHealthGoal)
                HStack { Text("Рекомендация:"); Spacer(); Text(recommendedGoalText).font(.caption2).foregroundStyle(.secondary) }
                HStack { Text("Сегодня (Health):"); Spacer(); Text(todayHealthText).font(.caption2).foregroundStyle(.secondary) }
                Button("Обновить из Health") { refreshHealthData() }.font(.caption2)
            }
            #endif

            NavigationLink("Напоминания") { ReminderSettingsView() }

            
            #if DEBUG
            Section("Сброс") {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text("Сбросить выпитое").font(.caption2)
                }
            }
            #endif

        }
        .navigationTitle("Настройки")
        .onChange(of: dailyGoalMl) { _ in
            AppGroup.sync(goal: dailyGoalMl)
        }
        #if canImport(HealthKit)
        .onChange(of: autoHealthGoal) { on in
            if on { applyRecommendedGoalIfAvailable() }
        }
        .onAppear {
            HealthService.shared.requestAuthorization { _, _ in
                refreshHealthData()
                if autoHealthGoal { applyRecommendedGoalIfAvailable() }
            }
        }
        #endif
        // Напоминания планируются на отдельном экране
        .alert("Сбросить счётчик?", isPresented: $showResetConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Сбросить", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    waterIntakeMl = 0
                }
                AppGroup.sync(water: 0)
            }
        } message: {
            Text("Текущее значение будет обнулено.")
        }
    }
}

#Preview {
    SettingsView()
}

#if canImport(HealthKit)
private extension SettingsView {
    var recommendedGoalText: String {
        if let v = recommendedGoalMl { return "\(Int(v)) мл/день" }
        return "—"
    }
    var todayHealthText: String {
        if let v = todayHealthMl { return "\(Int(v)) мл" }
        return "—"
    }
    func refreshHealthData() {
        HealthService.shared.computeRecommendedFromHealth { v in
            recommendedGoalMl = v
        }
        HealthService.shared.fetchTodayWaterTotalMl { v in
            todayHealthMl = v
        }
    }
    func applyRecommendedGoalIfAvailable() {
        if let v = recommendedGoalMl, v > 0 {
            dailyGoalMl = v
            AppGroup.sync(goal: dailyGoalMl)
        } else {
            HealthService.shared.computeRecommendedFromHealth { v in
                if let v { dailyGoalMl = v; AppGroup.sync(goal: v) }
            }
        }
    }
}
#endif

// Напоминания настроек находятся в ReminderSettingsView
