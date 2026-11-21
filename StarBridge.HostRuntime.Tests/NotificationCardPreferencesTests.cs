using StarBridge.HostRuntime.Notifications;


/// <summary>0.7.3 card preferences: separate file, one-time master switch, quiet-time rule and summary.</summary>
internal static class NotificationCardPreferencesTests
{
    internal static Task Run()
    {
        SeparateFile();
        MigrationRunsOnce();
        MigrationLeavesBrokenSettingsAlone();
        QuietRule();
        Summary();
        Console.WriteLine("PASS notification card preferences: separate file, one-time switch-on, quiet rule and summary");
        return Task.CompletedTask;
    }

    private static string Root()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-card-prefs-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }

    private static NotificationSettingsBridgeDispatcher Dispatcher(string root) => new(root, () => 1);

    private static void SeparateFile()
    {
        var root = Root();
        try
        {
            var store = new NotificationCardPreferencesStore(root);
            var defaults = store.Load();
            True(defaults.ShowDuringQuiet && defaults.QuietSummary && !defaults.WindowsMigrated073, "missing file reads as the decided defaults");
            File.WriteAllText(store.FilePath, "{ not json");
            True(store.Load() == new NotificationCardPreferences(), "a broken file reads as defaults");
            File.WriteAllText(store.FilePath, """{"schemaVersion":1,"showDuringQuiet":false,"quietSummary":true,"windowsMigrated073":true,"addedLater":5}""");
            var later = store.Load();
            True(!later.ShowDuringQuiet && later.WindowsMigrated073, "fields added by a later version are ignored, known ones kept");
            store.Save(later with { QuietSummary = false });
            True(!store.Load().QuietSummary, "saved value reads back");
            True(!File.Exists(Path.Combine(root, "notification-settings.v1.json")), "the card file never touches the existing settings file");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void MigrationRunsOnce()
    {
        var root = Root();
        try
        {
            var settingsPath = Path.Combine(root, "notification-settings.v1.json");
            // An existing 0.7.2 file with the switch off.
            File.WriteAllText(settingsPath, """{"schemaVersion":1,"revision":4,"inAppEnabled":true,"position":"bottomRight","preview":"sourceOnly","windowsEnabled":false}""");
            using var dispatcher = Dispatcher(root);
            var store = new NotificationCardPreferencesStore(root);
            True(dispatcher.MigrateWindowsCardsOn073(store), "first 0.7.3 start turns the Windows cards on");
            var after = dispatcher.InspectLocalSetup();
            True(after.WindowsEnabled && after.DirectMessageWindowsEnabled && after.Revision == 5, "master switch and direct-message cards on with the next revision", after);
            True(store.Load().WindowsMigrated073, "migration marked done");
            // The user turns it off again; later starts keep it off.
            File.WriteAllText(settingsPath, """{"schemaVersion":1,"revision":6,"inAppEnabled":true,"position":"bottomRight","preview":"sourceOnly","windowsEnabled":false}""");
            True(!dispatcher.MigrateWindowsCardsOn073(store) && !dispatcher.InspectLocalSetup().WindowsEnabled, "an off chosen after the migration stays off");
            // The old settings file keeps exactly its old fields, so an older version still reads it.
            using var json = System.Text.Json.JsonDocument.Parse(File.ReadAllText(settingsPath));
            True(json.RootElement.EnumerateObject().All(p => p.Name is "schemaVersion" or "revision" or "inAppEnabled" or "position" or "preview" or
                "windowsEnabled" or "overlayEnabled" or "directMessageWindowsEnabled" or "tradeWindowsEnabled" or "rallyAlerts"), "no new field in the old file");
        }
        finally { Directory.Delete(root, true); }
        var fresh = Root();
        try
        {
            using var dispatcher = Dispatcher(fresh);
            True(dispatcher.MigrateWindowsCardsOn073(new NotificationCardPreferencesStore(fresh)) && dispatcher.InspectLocalSetup().WindowsEnabled,
                "a device without a settings file also gets the switch on");
        }
        finally { Directory.Delete(fresh, true); }
    }

    private static void MigrationLeavesBrokenSettingsAlone()
    {
        var root = Root();
        try
        {
            var settingsPath = Path.Combine(root, "notification-settings.v1.json");
            File.WriteAllText(settingsPath, "{ broken");
            using var dispatcher = Dispatcher(root);
            var store = new NotificationCardPreferencesStore(root);
            True(!dispatcher.MigrateWindowsCardsOn073(store), "an unreadable settings file is not migrated");
            True(File.ReadAllText(settingsPath) == "{ broken" && !store.Load().WindowsMigrated073, "the file is untouched and the migration can run later");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void QuietRule()
    {
        True(SocialCardEnvironment.SuppressionReason(true, () => "do-not-disturb", () => "") == "", "show during quiet: do-not-disturb does not block");
        True(SocialCardEnvironment.SuppressionReason(true, () => "", () => "shell-suppressed-1") == "shell-suppressed-1", "a locked desktop still blocks");
        True(SocialCardEnvironment.SuppressionReason(false, () => "do-not-disturb", () => "") == "do-not-disturb", "turned off: the existing rule applies");
        True(SocialCardEnvironment.SuppressionReason(true, () => "", () => throw new InvalidOperationException()) == "unavailable", "a failing check blocks");
        True(SocialCardEnvironment.IsQuietReason("do-not-disturb") && SocialCardEnvironment.IsQuietReason("shell-suppressed-6") &&
            !SocialCardEnvironment.IsQuietReason("shell-suppressed-1") && !SocialCardEnvironment.IsQuietReason("shell-suppressed-2"),
            "only do-not-disturb and quiet time count as quiet");
    }

    private static void Summary()
    {
        var summary = new QuietCardSummary();
        True(summary.Take(true) is null, "nothing held, no summary");
        summary.Held("directMessage"); summary.Held("directMessage"); summary.Held("directMessage");
        summary.Held("online"); summary.Held("online");
        var text = summary.Take(true);
        True(text == "刚才有 3 条私信、2 条上线", $"summary text ({text})");
        True(summary.Take(true) is null, "one summary per quiet period");
        summary.Held("roomInvite"); summary.Reset();
        True(summary.Take(true) is null, "an account change clears what was held");
    }

    private static void True(bool value, string name, object? evidence = null)
    {
        if (!value) throw new InvalidOperationException(name + (evidence is null ? "" : " " + evidence));
    }
}
