//
//  ContentView.swift
//  WatchOfWater Watch App
//
//  Created by Дмитрий Козин on 31.08.2025.
//

import SwiftUI
import WatchKit
#if canImport(HealthKit)
import HealthKit
#endif

struct ContentView: View {
    @AppStorage("waterIntakeMl") private var waterIntakeMl: Double = 0
    @AppStorage("dailyGoalMl") private var dailyGoalMl: Double = 2000
    @AppStorage("quickAddStepMl") private var quickAddStepMl: Double = 200
    @State private var isPouring: Bool = false
    @AppStorage("lastIntakeDay") private var lastIntakeDay: String = ""
    @State private var showStepDialog: Bool = false
    @AppStorage("lastGoalAlertDay") private var lastGoalAlertDay: String = ""
    @State private var showGoalAlert: Bool = false

    private var progress: Double {
        guard dailyGoalMl > 0 else { return 0 }
        return min(max(waterIntakeMl / dailyGoalMl, 0), 1)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height) * 0.9
                VStack(spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        AnalogClockView(
                            date: context.date,
                            progress: progress,
                            waterText: "\(Int(waterIntakeMl)) / \(Int(dailyGoalMl)) мл",
                            isPouring: isPouring
                        )
                        .frame(width: size, height: size)
                    }

                    Text("\(Int(waterIntakeMl)) / \(Int(dailyGoalMl)) мл")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .onAppear {
                handleDayRolloverIfNeeded()
                AppGroup.sync(water: waterIntakeMl, goal: dailyGoalMl)
                // Health permissions (optional) — основную логику настройки цели переносим в Settings
                HealthService.shared.requestAuthorization { _, _ in }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack {
                        Image(systemName: "drop.fill")
                            .onTapGesture { addWater(amount: quickAddStepMl) }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                showStepDialog = true
                            }
                    }
                    .confirmationDialog("Выберите шаг добавления", isPresented: $showStepDialog, titleVisibility: .visible) {
                        Button("+50 мл") { addWater(amount: 50) }
                        Button("+100 мл") { addWater(amount: 100) }
                        Button("+200 мл") { addWater(amount: 200) }
                        Button("+300 мл") { addWater(amount: 300) }
                        Button("+500 мл") { addWater(amount: 500) }
                        Button("Отмена", role: .cancel) {}
                    }
                    .accessibilityLabel("Добавить воды")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .alert("Поздравляем!", isPresented: $showGoalAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Вы выполнили суточную норму по воде")
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.06, green: 0.10, blue: 0.20),
                    .black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

#Preview {
    ContentView()
}

// MARK: - Helpers

private func currentDayString(from date: Date = Date()) -> String {
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: date)
}

private extension ContentView {
    func addWater(amount: Double) {
        handleDayRolloverIfNeeded()
        let prev = waterIntakeMl
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            waterIntakeMl += amount
            isPouring = true
        }
        AppGroup.sync(water: waterIntakeMl, goal: dailyGoalMl)
        WKInterfaceDevice.current().play(.success)
        // Save sample to Health
        HealthService.shared.saveWaterIntake(ml: amount, at: Date(), completion: nil)
        checkGoalIfNeeded(previous: prev, current: waterIntakeMl)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.3)) { isPouring = false }
        }
    }
    func checkGoalIfNeeded(previous: Double, current: Double) {
        let today = currentDayString()
        guard lastGoalAlertDay != today else { return }
        guard dailyGoalMl > 0 else { return }
        guard previous < dailyGoalMl && current >= dailyGoalMl else { return }
        lastGoalAlertDay = today
        WKInterfaceDevice.current().play(.notification)
        showGoalAlert = true
    }
    func handleDayRolloverIfNeeded() {
        let today = currentDayString()
        if lastIntakeDay.isEmpty {
            lastIntakeDay = today
            return
        }
        if lastIntakeDay != today {
            waterIntakeMl = 0
            lastIntakeDay = today
        }
    }
}
