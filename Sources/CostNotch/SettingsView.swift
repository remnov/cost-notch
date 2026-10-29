import CursorCostCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("Provider") {
                Picker("AI provider", selection: bind(\.costProvider)) {
                    ForEach(CostProvider.allCases, id: \.self) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Display") {
                Toggle(showSecondaryTitle, isOn: bind(\.showToday))
                    .disabled(settings.preferences.minimalMode)
                Toggle("Minimal mode (\(settings.preferences.costProvider.currentLabel) only)", isOn: bind(\.minimalMode))
                Toggle("Show notch overlay", isOn: bind(\.showNotch))
                if settings.preferences.costProvider == .cursor {
                    Stepper(value: bind(\.recentQueryCount), in: 1...10) {
                        Text("Recent queries: \(settings.preferences.recentQueryCount)")
                    }
                    .disabled(settings.preferences.minimalMode)
                }
            }

            if settings.preferences.costProvider == .cursor {
                Section("Cursor") {
                    Toggle("Token-spike warning (!)", isOn: bind(\.showSpikeWarning))
                    Stepper(value: spikeK, in: 1...100_000, step: 100) {
                        Text("Warn at \(settings.preferences.spikeTokenThresholdK)k tokens")
                    }
                    Toggle("Critical alert", isOn: bind(\.showCriticalAlert))
                    Stepper(value: criticalK, in: 1...1_000_000, step: 500) {
                        Text("Alert at \(settings.preferences.criticalTokenThresholdK)k tokens")
                    }
                    Stepper(value: criticalUsd, in: 0.01...500, step: 0.5) {
                        Text("Alert at \(Formatting.dollars(settings.preferences.criticalCostUsdThreshold))")
                    }
                    Picker("Daily budget (Today cap)", selection: bind(\.budgetDayBasis)) {
                        Text("Working days (Mon–Fri)").tag(BudgetDayBasis.workingDays)
                        Text("Calendar days").tag(BudgetDayBasis.calendarDays)
                    }
                }
            } else {
                Section("Codex") {
                    Text("Reads ~/.codex/auth.json from the Codex CLI. Sign in with Codex, then Refresh.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Refresh") {
                Stepper(value: pollMinutes, in: 1...60) {
                    Text("Auto-refresh every \(settings.preferences.pollIntervalMinutes) min")
                }
            }

            Section {
                Button("Reset to defaults") {
                    settings.reset()
                    store.restartPolling()
                }
            }

            Section {
                Text("Cost Notch \(Self.version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 520)
        .onChange(of: settings.preferences.budgetDayBasis) { _ in
            Task { await store.refresh(allowKeychainInteraction: false) }
        }
        .onChange(of: settings.preferences.costProvider) { _ in
            Task { await store.refresh(allowKeychainInteraction: false) }
        }
    }

    private var showSecondaryTitle: String {
        "Show \(settings.preferences.costProvider.secondaryLabel)"
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
    }

    private func bind<Value>(_ keyPath: WritableKeyPath<NotchPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { settings.preferences[keyPath: keyPath] },
            set: { value in
                var next = settings.preferences
                next[keyPath: keyPath] = value
                next.clamp()
                settings.preferences = next
            }
        )
    }

    private var spikeK: Binding<Int> {
        Binding(
            get: { settings.preferences.spikeTokenThresholdK },
            set: { value in
                var next = settings.preferences
                next.spikeTokenThresholdK = value
                next.clamp()
                settings.preferences = next
            }
        )
    }

    private var criticalK: Binding<Int> {
        Binding(
            get: { settings.preferences.criticalTokenThresholdK },
            set: { value in
                var next = settings.preferences
                next.criticalTokenThresholdK = value
                next.clamp()
                settings.preferences = next
            }
        )
    }

    private var criticalUsd: Binding<Double> {
        Binding(
            get: { settings.preferences.criticalCostUsdThreshold },
            set: { value in
                var next = settings.preferences
                next.criticalCostUsdThreshold = value
                next.clamp()
                settings.preferences = next
            }
        )
    }

    private var pollMinutes: Binding<Int> {
        bind(\.pollIntervalMinutes)
    }
}
