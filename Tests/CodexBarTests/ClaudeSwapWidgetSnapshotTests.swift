import CodexBarCore
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarWidget

@MainActor
struct ClaudeSwapWidgetSnapshotTests {
    @Test
    func `Claude widget follows the active swap account even without account widgets`() async throws {
        let suite = "ClaudeSwapWidgetSnapshotTests-active"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.claudeSwapEnabled = true
        #expect(!settings.accountWidgetsEnabled)

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store._setSnapshotForTesting(self.usage(used: 100, now: now), provider: .claude)
        store.claudeSwapAccountSnapshots = [
            self.account(slot: "2", active: true, used: 44, now: now.addingTimeInterval(60)),
            self.account(slot: "1", active: false, used: 20, now: now.addingTimeInterval(60)),
        ]
        var snapshots: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { snapshots.append($0) }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "active-swap-widget-test")
        await store.widgetSnapshotPersistTask?.value
        let first = try #require(snapshots.last?.entries.first { $0.provider == .claude })
        #expect(first.primary?.usedPercent == 44)
        #expect(first.updatedAt == now.addingTimeInterval(60))
        #expect(first.quotaOwnerKey?.hasPrefix("claude/swap:2:") == true)
        #expect(snapshots.last?.accounts.isEmpty == true)

        store.claudeSwapAccountSnapshots = [
            self.account(slot: "1", active: true, used: 20, now: now.addingTimeInterval(120)),
            self.account(slot: "2", active: false, used: 44, now: now.addingTimeInterval(60)),
        ]
        store.persistWidgetSnapshot(reason: "switched-swap-widget-test")
        await store.widgetSnapshotPersistTask?.value
        let second = try #require(snapshots.last?.entries.first { $0.provider == .claude })
        #expect(second.primary?.usedPercent == 20)
        #expect(second.quotaOwnerKey?.hasPrefix("claude/swap:1:") == true)
        #expect(second.quotaOwnerKey != first.quotaOwnerKey)

        let spendAt = now.addingTimeInterval(150)
        let spend = ProviderCostSnapshot(used: 100, limit: 100, currencyCode: "USD", updatedAt: spendAt)
        store.claudeSwapAccountSnapshots = [
            ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "claude-swap", opaqueID: "1"),
                provider: .claude,
                displayLabel: "Account 1",
                accountEmail: "account1@example.test",
                isActive: true,
                snapshot: UsageSnapshot(
                    primary: nil, secondary: nil, providerCost: spend, updatedAt: spendAt),
                error: nil,
                sourceLabel: "claude-swap"),
            self.account(slot: "2", active: false, used: 44, now: now.addingTimeInterval(60)),
        ]
        store.persistWidgetSnapshot(reason: "spend-only-swap-widget-test")
        await store.widgetSnapshotPersistTask?.value
        let spendEntry = try #require(snapshots.last?.entries.first { $0.provider == .claude })
        #expect(spendEntry.primary == nil)
        #expect(spendEntry.usageRows?.first?.id == "extraUsage")
        #expect(spendEntry.usageRows?.first?.percentLeft == 0)
        #expect(spendEntry.quotaOwnerKey?.hasPrefix("claude/swap:1:") == true)

        store.claudeSwapAccountSnapshots = [
            self.account(slot: "2", active: true, used: nil, now: now.addingTimeInterval(180)),
            self.account(slot: "1", active: false, used: 20, now: now.addingTimeInterval(120)),
        ]
        store.persistWidgetSnapshot(reason: "unavailable-swap-widget-test")
        await store.widgetSnapshotPersistTask?.value
        #expect(snapshots.last?.entries.first { $0.provider == .claude }?.primary == nil)
    }

    @Test
    func `multi account widget filters by enabled provider and keeps active account`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let active = self.account(slot: "2", active: true, used: 44, now: now)
        let inactive = self.account(slot: "1", active: false, used: 20, now: now)
        let entries = [active, inactive].map { account in
            WidgetSnapshot.AccountEntry(
                id: account.id.opaqueID,
                provider: .claude,
                label: "Account \(account.id.opaqueID)",
                usage: account.snapshot.map { snapshot in
                    WidgetSnapshot.ProviderEntry(
                        provider: .claude,
                        updatedAt: snapshot.updatedAt,
                        primary: snapshot.primary,
                        secondary: nil,
                        tertiary: nil,
                        creditsRemaining: nil,
                        codeReviewRemainingPercent: nil,
                        tokenUsage: nil,
                        dailyUsage: [])
                },
                isActive: account.isActive)
        }
        let snapshot = WidgetSnapshot(entries: [], accounts: entries, enabledProviders: [.claude], generatedAt: now)
        let visible = CodexBarAccountsWidgetView.accounts(in: snapshot, for: .claude)
        #expect(visible.count == 2)
        #expect(visible.first?.isActive == true)
        #expect(visible.map(\.usage?.primary?.usedPercent) == [44, 20])
        #expect(CodexBarAccountsWidgetView.accounts(in: snapshot, for: .codex).isEmpty)
        let disabled = WidgetSnapshot(entries: [], accounts: entries, enabledProviders: [], generatedAt: now)
        #expect(CodexBarAccountsWidgetView.accounts(in: disabled, for: .claude).isEmpty)

        let spendOnly = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            usageRows: [.init(
                id: "extraUsage",
                title: "Extra usage",
                percentLeft: 0,
                window: RateWindow(usedPercent: 100, windowMinutes: nil, resetsAt: nil, resetDescription: nil))],
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let spendMetrics = CodexBarAccountsWidgetView.metrics(for: spendOnly)
        #expect(spendMetrics.first?.title == "Extra usage")
        #expect(spendMetrics.first?.percentLeft == 0)
    }

    private func usage(used: Double, now: Date) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: used, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: now)
    }

    private func account(slot: String, active: Bool, used: Double?, now: Date) -> ProviderAccountUsageSnapshot {
        ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "claude-swap", opaqueID: slot),
            provider: .claude,
            displayLabel: "Account \(slot)",
            accountEmail: "account\(slot)@example.test",
            isActive: active,
            snapshot: used.map { self.usage(used: $0, now: now) },
            error: nil,
            sourceLabel: "claude-swap")
    }
}
