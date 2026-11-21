using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class AnnouncementDefaultFollowTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "default-follow-synthetic");
    private static readonly DateTimeOffset Day = new(2026, 11, 8, 12, 0, 0, TimeSpan.Zero);
    private static readonly NotificationEventKind Kind = NotificationEventKind.OrganizationAnnouncement;
    private static int _checks;
    private static void Check(bool value, string message) { _checks++; if (!value) throw new Exception(message); }

    internal static Task Run()
    {
        _checks = 0;
        foreach (var source in new[] { NotificationPolicyStore.Organization("SYNTHETIC", Day.AddDays(-1)),
            NotificationPolicyStore.OfficialFleet("officialFleet:7") }) {
            foreach (var types in new NotificationTypeRule[]?[] { null, [], [new("chat", "disabled")] }) {
                foreach (var mode in Enum.GetValues<NotificationSourceMode>()) {
                    var rule = new NotificationPolicyRule(source, mode) { TypeRules = types };
                    var allowed = mode == NotificationSourceMode.Normal;
                    // Deliberately bypass CardRule: reverting the card feature cannot revert this default.
                    Check(NotificationOrganizationPolicy.Allows(rule, Kind, Day, TimeZoneInfo.Utc) == allowed,
                        "Missing announcement follows source mode in Allows without CardRule: " + mode);
                    Check(NotificationOrganizationPolicy.AllowsCard(rule, Kind, Day, Day, TimeZoneInfo.Utc) == allowed,
                        "Missing announcement follows source mode for cards: " + mode);
                    Check(NotificationOrganizationPolicy.CardRule(rule, Kind)!.TypeRules!.Single(t => t.Type == "announcement").Mode == "inherit",
                        "CardRule adds inherit, not an independent enabled choice.");
                    Check(rule.TypeRules == types && rule.TypeRules?.Any(t => t.Type == "announcement") != true,
                        "Evaluating the default never mutates the saved rule.");
                }
            }
            foreach (var choice in new[] { "inherit", "enabled", "disabled" }) {
                var rule = new NotificationPolicyRule(source, NotificationSourceMode.Normal) { TypeRules = [new("announcement", choice)] };
                Check(NotificationOrganizationPolicy.Allows(rule, Kind, Day, TimeZoneInfo.Utc) == (choice != "disabled") &&
                    NotificationOrganizationPolicy.AllowsCard(rule, Kind, Day, Day, TimeZoneInfo.Utc) == (choice != "disabled"),
                    "All explicit choices retain their delivery behavior: " + choice);
                Check(ReferenceEquals(NotificationOrganizationPolicy.CardRule(rule, Kind), rule), "CardRule preserves an explicit choice.");
            }
            var quiet = new NotificationPolicyRule(source, NotificationSourceMode.Normal) { QuietHours = new(true, 720, 721) };
            Check(!NotificationOrganizationPolicy.Allows(quiet, Kind, Day, TimeZoneInfo.Utc) &&
                !NotificationOrganizationPolicy.AllowsCard(quiet, Kind, Day, Day, TimeZoneInfo.Utc), "Daily quiet hours suppress both default paths.");
            var after = Day.AddMinutes(1);
            Check(!NotificationOrganizationPolicy.AllowsEvent(quiet, Kind, Day, after, TimeZoneInfo.Utc) &&
                !NotificationOrganizationPolicy.AllowsCard(quiet, Kind, Day, after, TimeZoneInfo.Utc), "An event skipped during quiet hours cannot reappear afterward.");
            Check(NotificationOrganizationPolicy.AllowsEvent(quiet, Kind, after, after, TimeZoneInfo.Utc) &&
                NotificationOrganizationPolicy.AllowsCard(quiet, Kind, after, after, TimeZoneInfo.Utc), "New post-quiet events follow the source again.");
        }
        Persistence();
        Console.WriteLine($"PASS CX-ANNOUNCE-DEFAULT-FOLLOW: {_checks} assertions, 0 failed");
        return Task.CompletedTask;
    }

    private static void Persistence()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-default-follow-" + Guid.NewGuid().ToString("N"));
        try {
            var store = new NotificationPolicyStore(root);
            var sources = new[] { NotificationPolicyStore.Organization("SYNTHETIC", Day.AddDays(-1)),
                NotificationPolicyStore.OfficialFleet("officialFleet:7") };
            var missing = store.Read(Owner);
            Check(!Directory.Exists(root) && sources.All(source => NotificationOrganizationPolicy.Allows(missing.Rule(source), Kind, Day, TimeZoneInfo.Utc)),
                "Fresh organization and official-fleet defaults follow without creating or migrating files.");
            var saved = store.Save(Owner, 0, Guid.NewGuid().ToString("N"), sources.Select(source =>
                new NotificationPolicyRule(source, NotificationSourceMode.Normal) { TypeRules = [new("announcement", "disabled")] }).ToArray(),
                () => true, extended: true);
            var bytes = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).ToDictionary(path => path, File.ReadAllBytes);
            var read = new NotificationPolicyStore(root).Read(Owner);
            Check(read.Revision == saved.Revision && sources.All(source => read.Rule(source).TypeRules!.Single().Mode == "disabled" &&
                !NotificationOrganizationPolicy.Allows(read.Rule(source), Kind, Day, TimeZoneInfo.Utc) &&
                !NotificationOrganizationPolicy.AllowsCard(read.Rule(source), Kind, Day, Day, TimeZoneInfo.Utc)),
                "Existing v2 disabled choices remain disabled for cards and ordinary delivery.");
            Check(bytes.All(file => file.Value.SequenceEqual(File.ReadAllBytes(file.Key))), "Reading existing v2 choices preserves every file byte.");
            // The legacy save contract still merges and preserves v2 extension rows.
            var legacy = store.Save(Owner, read.Revision, Guid.NewGuid().ToString("N"), sources.Select(source =>
                new NotificationPolicyRule(source, NotificationSourceMode.ImportantOnly)).ToArray(), () => true);
            Check(sources.All(source => legacy.Rule(source).TypeRules!.Single().Mode == "disabled"), "Old-client saves keep the v2 announcement choice.");
        } finally {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    internal static async Task Reconciliation()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-default-reconciliation-" + Guid.NewGuid().ToString("N"));
        try { await NotificationReconciliationWriteTests.Run(root); }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
