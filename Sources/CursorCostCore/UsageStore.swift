import Combine
import Foundation

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

    public var dashboardURL: URL {
        settings.preferences.costProvider.dashboardURL
    }

    public var dashboardMenuTitle: String {
        settings.preferences.costProvider.dashboardMenuTitle
    }

    private let client: CursorAPIClient
    private let codexClient: CodexAPIClient
    private let settings: AppSettings
    private var pollTask: Task<Void, Never>?
    private var refreshID = UUID()
    private var cancellables: Set<AnyCancellable> = []

    public init(
        client: CursorAPIClient = CursorAPIClient(),
        codexClient: CodexAPIClient = CodexAPIClient(),
        settings: AppSettings
    ) {
        self.client = client
        self.codexClient = codexClient
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
        settings.$preferences
            .map(\.costProvider)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.snapshot = .loading
                self?.lastUpdated = nil
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
        let request = UUID()
        refreshID = request
        isRefreshing = true
        defer {
            if refreshID == request {
                isRefreshing = false
            }
        }
        let provider = settings.preferences.costProvider
        do {
            let ready: UsageReady
            switch provider {
            case .cursor:
                let auth = try await Task.detached(priority: .utility) {
                    try CursorSessionStore.readAuth(allowKeychainInteraction: allowKeychainInteraction)
                }.value
                let session = try await client.session(from: auth)
                ready = try await client.loadUsage(
                    cookie: session.cookie,
                    email: session.email,
                    budgetDayBasis: settings.preferences.budgetDayBasis
                )
            case .codex:
                let auth = try await Task.detached(priority: .utility) {
                    try CodexSessionStore.readAuth()
                }.value
                ready = try await codexClient.loadUsage(auth: auth)
            }
            guard refreshID == request, settings.preferences.costProvider == provider else { return }
            snapshot = .ready(ready)
            lastUpdated = Date()
        } catch let error as CursorCostError {
            guard refreshID == request, settings.preferences.costProvider == provider else { return }
            snapshot = snapshot.failing(with: error.errorDescription ?? "Could not load usage")
        } catch {
            guard refreshID == request, settings.preferences.costProvider == provider else { return }
            snapshot = snapshot.failing(with: CursorCostError.loadUsage.errorDescription ?? "Could not load usage")
        }
    }
}
