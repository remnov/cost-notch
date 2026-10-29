import AppKit
import CursorCostCore
import SwiftUI

struct NotchContentView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var viewModel: NotchViewModel
    var onOpenSettings: () -> Void = {}

    private var topRadius: CGFloat { viewModel.isExpanded ? 19 : 6 }
    private var bottomRadius: CGFloat { viewModel.isExpanded ? 24 : 14 }
    private var presentation: UsagePresentation { store.presentation }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                if viewModel.isExpanded {
                    NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                        .fill(Color.black)
                        .shadow(color: toneColor(presentation.currentTone).opacity(0.18), radius: 10, y: 4)
                        .padding(.horizontal, viewModel.geometry.shadowPadding)
                        .padding(.bottom, 8)
                }

                Group {
                    if viewModel.isExpanded {
                        expandedContent
                            .padding(.top, viewModel.geometry.notchHeight + 8)
                            .padding(.bottom, bottomRadius + 6)
                    } else {
                        collapsedContent
                    }
                }
                .padding(.horizontal, viewModel.isExpanded ? viewModel.geometry.shadowPadding + topRadius + 4 : 0)
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: viewModel.isExpanded)
            .ignoresSafeArea()
        }
    }

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            Text(presentation.currentCompact)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(toneColor(presentation.currentTone))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .center)

            Color.clear.frame(width: max(viewModel.geometry.notchWidth - 28, 40))

            Color.clear
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cost Notch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if store.isRefreshing || presentation.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .colorScheme(.dark)
                }
            }

            providerSection(presentation.providerTitle) {
                spendBarRow(
                    title: presentation.currentLabel,
                    value: presentation.currentText,
                    tone: presentation.currentTone,
                    progress: presentation.currentProgress
                )
                if let today = presentation.todayText {
                    spendBarRow(
                        title: presentation.todayLabel,
                        value: today,
                        tone: presentation.todayTone,
                        progress: presentation.todayProgress
                    )
                }

                if presentation.recent.isEmpty || presentation.isStale {
                    Text(presentation.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                        .help(presentation.statusMessage)
                }
                if !presentation.recent.isEmpty {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(presentation.recent) { query in
                                HStack {
                                    Text(query.model)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.55))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(query.text)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(toneColor(query.tone))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 88)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                notchButton(title: "Refresh") {
                    Task { await store.refresh() }
                }
                notchButton(title: "Dashboard") {
                    NSWorkspace.shared.open(store.dashboardURL)
                }
                notchButton(title: "Settings") {
                    onOpenSettings()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let plan = presentation.plan {
                        Text(plan)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    if let email = presentation.email {
                        Text(email)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.28))
                            .lineLimit(1)
                    }
                    if let updated = store.lastUpdated {
                        Text((presentation.isStale ? "Stale · " : "") + Formatting.shortTime(updated))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.28))
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 6)
    }

    private func providerSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func spendBarRow(title: String, value: String, tone: SpendTone, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(toneColor(tone))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let progress {
                spendBar(progress: progress, tone: tone)
            }
        }
        .padding(.vertical, 4)
    }

    private func spendBar(progress: Double, tone: SpendTone) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(height: 7)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(toneColor(tone))
                    .scaleEffect(x: min(1, max(0, progress)), y: 1, anchor: .leading)
            }
            .clipShape(Capsule())
    }

    private func notchButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func toneColor(_ tone: SpendTone) -> Color {
        switch tone {
        case .red:
            return Color(red: 0.945, green: 0.298, blue: 0.298)
        case .green:
            return Color(red: 0.537, green: 0.820, blue: 0.522)
        case .default:
            return .white.opacity(0.85)
        }
    }
}
