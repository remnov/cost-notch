import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var cursorSnapshot: UsageSnapshot = .loading
    @Published public private(set) var codexSnapshot: UsageSnapshot = .loading
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastUpdated: Date?

    public var snapshot: UsageSnapshot {
        snapshot(for: settings.preferences.costProvider)
    }

    public var isDualView: Bool {
        settings.preferences.dualView
    }

    public var presentation: UsagePresentation {
        presentation(for: settings.preferences.costProvider)
    }

    public var visiblePresentations: [(provider: CostProvider, presentation: UsagePresentation)] {
        settings.preferences.visibleProviders.map { provider in
            (provider, presentation(for: provider))
        }
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
            .map { ($0.dualView, $0.costProvider) }
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartPolling()
            }
            .store(in: &cancellables)
    }

    public func snapshot(for provider: CostProvider) -> UsageSnapshot {
        switch provider {
        case .cursor:
            return cursorSnapshot
        case .codex:
            return codexSnapshot
        }
    }

    public func presentation(for provider: CostProvider) -> UsagePresentation {
        UsageMapper.presentation(
            snapshot(for: provider),
            now: Date(),
            refreshing: isRefreshing,
            preferences: settings.preferences,
            provider: provider
        )
    }

    public func dashboardURL(for provider: CostProvider) -> URL {
        provider.dashboardURL
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
        let providers = settings.preferences.visibleProviders
        let loadCursor = providers.contains(.cursor)
        let loadCodex = providers.contains(.codex)
        let cursor: Result<UsageReady, Error>?
        let codex: Result<UsageReady, Error>?
        if loadCursor, loadCodex {
            async let cursorLoad = loadCursorUsage(allowKeychainInteraction: allowKeychainInteraction)
            async let codexLoad = loadCodexUsage()
            cursor = await cursorLoad
            codex = await codexLoad
        } else if loadCursor {
            cursor = await loadCursorUsage(allowKeychainInteraction: allowKeychainInteraction)
            codex = nil
        } else if loadCodex {
            cursor = nil
            codex = await loadCodexUsage()
        } else {
            cursor = nil
            codex = nil
        }
        guard refreshID == request else { return }
        var didSucceed = false
        if let cursor {
            cursorSnapshot = applied(cursor, to: cursorSnapshot)
            if case .success = cursor {
                didSucceed = true
            }
        }
        if let codex {
            codexSnapshot = applied(codex, to: codexSnapshot)
            if case .success = codex {
                didSucceed = true
            }
        }
        if didSucceed {
            lastUpdated = Date()
        }
    }
}

private extension UsageStore {
    func loadCursorUsage(allowKeychainInteraction: Bool) async -> Result<UsageReady, Error> {
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
            return .success(ready)
        } catch {
            return .failure(error)
        }
    }

    func loadCodexUsage() async -> Result<UsageReady, Error> {
        do {
            let auth = try await Task.detached(priority: .utility) {
                try CodexSessionStore.readAuth()
            }.value
            let ready = try await codexClient.loadUsage(auth: auth)
            return .success(ready)
        } catch {
            return .failure(error)
        }
    }

    func applied(_ result: Result<UsageReady, Error>, to current: UsageSnapshot) -> UsageSnapshot {
        switch result {
        case .success(let ready):
            return .ready(ready)
        case .failure(let error as CursorCostError):
            return current.failing(with: error.errorDescription ?? "Could not load usage")
        case .failure:
            return current.failing(with: CursorCostError.loadUsage.errorDescription ?? "Could not load usage")
        }
    }
}
