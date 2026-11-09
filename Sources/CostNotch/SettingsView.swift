import CursorCostCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var updates: AppUpdateController

    var body: some View {
        Form {
            Section("Provider") {
                Toggle("Show Cursor and Codex together", isOn: bind(\.dualView))
                if settings.preferences.dualView {
                    Picker("Notch pill", selection: bind(\.pillLeftProvider)) {
                        Text("Cursor left · Codex right").tag(CostProvider.cursor)
                        Text("Codex left · Cursor right").tag(CostProvider.codex)
                    }
                } else {
                    Picker("AI provider", selection: bind(\.costProvider)) {
                        ForEach(CostProvider.allCases, id: \.self) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Display") {
                Toggle(showSecondaryTitle, isOn: bind(\.showToday))
                    .disabled(settings.preferences.minimalMode)
                Toggle(minimalModeTitle, isOn: bind(\.minimalMode))
                Toggle("Show notch overlay", isOn: bind(\.showNotch))
                Stepper(value: bind(\.expandDelaySeconds), in: 0...2, step: 0.1) {
                    Text("Expand after \(Self.durationLabel(settings.preferences.expandDelaySeconds))")
                }
                Stepper(value: bind(\.hideDelaySeconds), in: 0...2, step: 0.1) {
                    Text("Hide after leaving \(Self.durationLabel(settings.preferences.hideDelaySeconds))")
                }
                if showsCursor {
                    Stepper(value: bind(\.recentQueryCount), in: 1...10) {
                        Text("Recent queries: \(settings.preferences.recentQueryCount)")
                    }
                    .disabled(settings.preferences.minimalMode)
                }
            }

            if showsCursor {
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
            }

            if showsCodex {
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
                VStack(spacing: 8) {
                    Text("Cost Notch \(Self.version)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(updates.isChecking ? "Checking…" : "Check for Updates") {
                        Task { await updates.checkForUpdates() }
                    }
                    .disabled(updates.isChecking || updates.isInstalling)
                    if let version = updates.offeredVersion {
                        Button(updates.isInstalling ? "Updating…" : "Update to \(version)") {
                            Task { await updates.install() }
                        }
                        .disabled(updates.isInstalling)
                    }
                    if let message = updates.statusMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 640)
        .onChange(of: settings.preferences.budgetDayBasis) { _ in
            Task { await store.refresh(allowKeychainInteraction: false) }
        }
        .onChange(of: settings.preferences.costProvider) { _ in
            Task { await store.refresh(allowKeychainInteraction: false) }
        }
        .onChange(of: settings.preferences.dualView) { _ in
            Task { await store.refresh(allowKeychainInteraction: false) }
        }
    }

    private var showsCursor: Bool {
        settings.preferences.shows(.cursor)
    }

    private var showsCodex: Bool {
        settings.preferences.shows(.codex)
    }

    private var showSecondaryTitle: String {
        if settings.preferences.dualView {
            return "Show Today / Weekly"
        }
        return "Show \(settings.preferences.costProvider.secondaryLabel)"
    }

    private var minimalModeTitle: String {
        if settings.preferences.dualView {
            return "Minimal mode (compact only)"
        }
        return "Minimal mode (\(settings.preferences.costProvider.currentLabel) only)"
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let hundredths = Int((seconds * 100).rounded())
        if hundredths % 100 == 0 {
            return "\(hundredths / 100) s"
        }
        if hundredths % 10 == 0 {
            return "\(hundredths / 100).\(hundredths / 10 % 10) s"
        }
        return "\(hundredths / 100).\(hundredths / 10 % 10)\(hundredths % 10) s"
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.4"
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
