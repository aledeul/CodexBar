import AppIntents
import CodexBarCore
import SwiftUI
import WidgetKit

struct CodexBarAccountUsageWidget: Widget {
    private let kind = "CodexBarAccountUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: AccountUsageSelectionIntent.self,
            provider: CodexBarAccountTimelineProvider())
        { entry in
            CodexBarAccountUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Account Usage")
        .description("Usage limits and reset countdowns for one saved account.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CodexBarAccountsWidget: Widget {
    private let kind = "CodexBarAccountsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: CodexBarTimelineProvider())
        { entry in
            CodexBarAccountsWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Accounts")
        .description("Usage for multiple accounts of one provider.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CodexBarAccountsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarWidgetEntry

    var accounts: [WidgetSnapshot.AccountEntry] {
        Self.accounts(in: self.entry.snapshot, for: self.entry.provider)
    }

    static func accounts(in snapshot: WidgetSnapshot, for provider: UsageProvider) -> [WidgetSnapshot.AccountEntry] {
        guard snapshot.enabledProviders.contains(provider.instanceID) else { return [] }
        return snapshot.accounts.filter { $0.provider == provider.instanceID }
    }

    var body: some View {
        let accounts = self.accounts
        let visibleCount = self.family == .systemLarge ? 5 : 2
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProviderMark(provider: self.entry.provider, isSelected: true, size: 20)
                Text(ProviderDefaults.metadata[self.entry.provider]?.displayName
                    ?? self.entry.provider.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                Text("Accounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if accounts.isEmpty {
                WidgetEmptyState(message: "Enable account widgets in CodexBar Settings → Menu → Widgets.")
            } else {
                ForEach(accounts.prefix(visibleCount)) { account in
                    self.accountRow(account)
                }
                if accounts.count > visibleCount {
                    Text("+\(accounts.count - visibleCount) more in CodexBar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func accountRow(_ account: WidgetSnapshot.AccountEntry) -> some View {
        let metrics = Self.metrics(for: account.usage)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(account.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if account.isActive {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let usage = account.usage {
                    FreshnessLabel(updatedAt: usage.updatedAt)
                }
            }
            if !metrics.isEmpty {
                HStack(spacing: 12) {
                    ForEach(metrics) { metric in
                        self.metric(metric)
                    }
                }
            } else {
                Text("Usage unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ metric: WidgetUsageRow) -> some View {
        let value = self.entry.snapshot.usageBarsShowUsed
            ? metric.percentLeft.map { 100 - $0 }
            : metric.percentLeft
        return HStack(spacing: 3) {
            Text(metric.title)
                .foregroundStyle(.secondary)
            Text(WidgetFormat.percent(value))
                .fontWeight(.semibold)
            Text(self.entry.snapshot.usageBarsShowUsed ? "used" : "left")
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
    }

    static func metrics(for usage: WidgetSnapshot.ProviderEntry?) -> [WidgetUsageRow] {
        guard let usage else { return [] }
        return Array(WidgetUsageRow.rows(for: usage).filter { $0.percentLeft != nil }.prefix(2))
    }
}

struct AccountUsageSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account Usage"
    static let description = IntentDescription("Select the provider and account to display in the widget.")

    /// Provider-specific by design: keep the same initial provider as the established Usage widget intent.
    @Parameter(title: "Provider", default: .codex)
    var provider: ProviderChoice

    @Parameter(title: "Account")
    var account: WidgetAccountEntity?

    init() {
        self.provider = .codex
    }
}

struct CodexBarAccountWidgetEntry: TimelineEntry {
    let usageEntry: CodexBarWidgetEntry
    let accountID: String?

    var date: Date {
        self.usageEntry.date
    }

    var accountLabel: String? {
        let provider = self.usageEntry.provider.instanceID
        guard let accountID, self.usageEntry.snapshot.enabledProviders.contains(provider) else { return nil }
        // Saved intent labels may predate privacy changes; only the current snapshot may supply identity.
        return self.usageEntry.snapshot.account(id: accountID, provider: provider)?.label
    }
}

struct CodexBarAccountTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CodexBarAccountWidgetEntry {
        let now = Date()
        let usage = WidgetSnapshot.ProviderEntry(
            // Provider-specific by design: gallery previews use the established synthetic Codex quota fixture.
            provider: .codex,
            updatedAt: now,
            primary: RateWindow(usedPercent: 35, windowMinutes: 300, resetsAt: nil, resetDescription: "Resets in 4h"),
            secondary: RateWindow(
                usedPercent: 60,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: "Resets in 3d"),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        return Self.makeEntry(
            snapshot: WidgetSnapshot(
                entries: [],
                // Provider-specific by design: this preview account and its provider belong to the same fixture.
                accounts: [.init(id: "preview", provider: .codex, label: "Personal", usage: usage)],
                enabledProviders: [.codex],
                generatedAt: now),
            provider: .codex,
            accountID: "preview",
            now: now)
    }

    func snapshot(
        for configuration: AccountUsageSelectionIntent,
        in context: Context) async -> CodexBarAccountWidgetEntry
    {
        if context.isPreview, configuration.account == nil {
            return self.placeholder(in: context)
        }
        return Self.makeEntry(
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot(),
            provider: configuration.provider.provider,
            accountID: configuration.account?.id,
            now: Date())
    }

    func timeline(
        for configuration: AccountUsageSelectionIntent,
        in context: Context) async -> Timeline<CodexBarAccountWidgetEntry>
    {
        let entry = Self.makeEntry(
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot(),
            provider: configuration.provider.provider,
            accountID: configuration.account?.id,
            now: Date())
        let refresh = BurnDownRefreshSchedule.nextRefresh(
            snapshot: entry.usageEntry.snapshot,
            provider: entry.usageEntry.provider,
            now: entry.date)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    static func makeEntry(
        snapshot: WidgetSnapshot,
        provider: UsageProvider,
        accountID: String?,
        now: Date) -> CodexBarAccountWidgetEntry
    {
        let selected: WidgetSnapshot = if let accountID {
            snapshot.selectingAccount(accountID, for: provider)
        } else {
            // An unconfigured account widget must not inherit the provider's active account.
            WidgetSnapshot(
                entries: [],
                accounts: snapshot.accounts,
                enabledProviders: snapshot.enabledProviders,
                usageBarsShowUsed: snapshot.usageBarsShowUsed,
                generatedAt: snapshot.generatedAt)
        }
        return CodexBarAccountWidgetEntry(
            usageEntry: CodexBarWidgetEntry(date: now, provider: provider, snapshot: selected),
            accountID: accountID)
    }
}

struct CodexBarAccountUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodexBarAccountWidgetEntry

    var body: some View {
        if self.entry.accountID == nil {
            self.notice(
                title: "Choose an account",
                message: "Enable account widgets in CodexBar → Settings → Menu → Widgets. "
                    + "Then edit this widget to choose an account.")
        } else if let usage = self.entry.usageEntry.snapshot.entries.first(where: {
            $0.provider == self.entry.usageEntry.provider.instanceID
        }) {
            UsageTile(entry: usage, size: WidgetTileSize(family: self.family)) {
                VStack(alignment: .leading, spacing: 3) {
                    TileHeader(
                        provider: usage.provider,
                        updatedAt: usage.updatedAt,
                        size: WidgetTileSize(family: self.family))
                    if let label = self.entry.accountLabel {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.fill.tertiary, for: .widget)
            .environment(\.widgetUsageShowsUsed, self.entry.usageEntry.snapshot.usageBarsShowUsed)
        } else {
            self.notice(
                title: "Account unavailable",
                message: "Open CodexBar to refresh, or edit this widget to choose another account.")
        }
    }

    private func notice(title: String, message: String) -> some View {
        let provider = self.entry.usageEntry.provider
        let providerName = ProviderDefaults.metadata[provider]?.displayName ?? provider.rawValue.capitalized
        return VStack(alignment: .leading, spacing: 6) {
            Text(self.entry.accountLabel.map { "\(providerName) · \($0)" } ?? providerName)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
