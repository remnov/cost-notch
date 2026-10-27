import Combine
import Foundation

public enum CursorLinks {
    public static let dashboard = URL(string: "https://cursor.com/dashboard")!
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot = .loading
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastUpdated: Date?

    public var presentation: UsagePresentation {
        UsageMapper.presentation(
            snapshot,
            now: Date(),
            refreshing: isRefreshing,
            preferences: settings.preferences
        )
    }

    private let client: CursorAPIClient
    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init(client: CursorAPIClient = CursorAPIClient(), settings: AppSettings) {
        self.client = client
        self.settings = settings
        settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        settings.$preferences
            .map(\.pollIntervalMinutes)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartPolling()
            }
            .store(in: &cancellables)
    }

    public func start() {
        restartPolling()
    }

    public func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh(allowKeychainInteraction: false)
                let seconds = Double(self.settings.preferences.pollIntervalMinutes) * 60
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    public func refresh(allowKeychainInteraction: Bool = true) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let auth = try await Task.detached(priority: .utility) {
                try CursorSessionStore.readAuth(allowKeychainInteraction: allowKeychainInteraction)
            }.value
            let session = try await client.session(from: auth)
            let ready = try await client.loadUsage(
                cookie: session.cookie,
                email: session.email,
                budgetDayBasis: settings.preferences.budgetDayBasis
            )
            snapshot = .ready(ready)
            lastUpdated = Date()
        } catch let error as CursorCostError {
            snapshot = snapshot.failing(with: error.errorDescription ?? "Could not load usage")
        } catch {
            snapshot = snapshot.failing(with: CursorCostError.loadUsage.errorDescription ?? "Could not load usage")
        }
    }
}
