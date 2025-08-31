import SwiftUI
import UserNotifications

struct ReminderSettingsView: View {
    @AppStorage("remindersEnabled") private var remindersEnabled: Bool = false
    @AppStorage("remindersCount") private var remindersCount: Int = 6
    @AppStorage("wakeStartMinutes") private var wakeStartMinutes: Int = 8 * 60
    @AppStorage("wakeEndMinutes") private var wakeEndMinutes: Int = 22 * 60
    @AppStorage("remindersAutoWake") private var remindersAutoWake: Bool = true
    @AppStorage("remindersPersonalized") private var remindersPersonalized: Bool = false

    var body: some View {
        Form {
            Section("Напоминания") {
                Toggle("Включить", isOn: $remindersEnabled)
                Toggle("Автоопределение бодрствования", isOn: $remindersAutoWake)
                Toggle("Индивидуальные напоминания", isOn: $remindersPersonalized)
                Stepper(value: $remindersCount, in: 1...12) {
                    Text("Количество: \(remindersCount)").font(.caption2)
                }
            }
            if !remindersAutoWake {
                Section("Бодрствование") {
                    Stepper(value: $wakeStartMinutes, in: 0...(23*60), step: 30) {
                        Text("Начало: \(timeString(wakeStartMinutes))").font(.caption2)
                    }
                    Stepper(value: $wakeEndMinutes, in: 60...(24*60), step: 30) {
                        Text("Конец: \(timeString(wakeEndMinutes))").font(.caption2)
                    }
                }
            }
            #if DEBUG
            Section("Отладка") {
                Button("Тестовое уведомление") { ReminderService.sendTestNotification() }
                    .font(.caption2)
            }
            #endif
            Section(footer: Text("Уведомления планируются автоматически при изменении настроек. Убедитесь, что разрешены уведомления и доступ к Здоровью для сна/активности.")) {
                EmptyView()
            }
        }
        .navigationTitle("Напоминания")
        .onAppear {
            // Попросим доступ к Health, если нужны авто‑сон или персонализация
            if remindersAutoWake || remindersPersonalized {
                HealthService.shared.requestAuthorization { _, _ in }
            }
            schedule()
        }
        .onChange(of: remindersEnabled) { _ in schedule() }
        .onChange(of: remindersCount) { _ in schedule() }
        .onChange(of: wakeStartMinutes) { _ in schedule() }
        .onChange(of: wakeEndMinutes) { _ in schedule() }
        .onChange(of: remindersAutoWake) { _ in schedule() }
        .onChange(of: remindersPersonalized) { _ in schedule() }
    }

    private func schedule() {
        let cfg = ReminderConfig(enabled: remindersEnabled, count: remindersCount, startMinutes: wakeStartMinutes, endMinutes: wakeEndMinutes)
        ReminderService.schedule(config: cfg, personalized: remindersPersonalized, autoWaking: remindersAutoWake, completion: nil)
    }

    private func timeString(_ minutes: Int) -> String {
        let m = max(0, min(24*60, minutes))
        let h = m / 60
        let min = m % 60
        return String(format: "%02d:%02d", h, min)
    }
}

#Preview { ReminderSettingsView() }

