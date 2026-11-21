using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class OfficialDefaultIntentTests
{
    internal static async Task MissingIntent()
    {
        // Omitted intent must preserve unasked consent for manual choices,
        // inherited membership choices, community scopes and partial choices.
        foreach (bool? intent in new bool?[] { null, false })
        foreach (var scenario in new[] { "manual", "inherited", "community", "partial" })
        {
            var root = Path.Combine(Path.GetTempPath(), "consent-b2-" + Guid.NewGuid().ToString("N"));
            var owner = new BridgeAccountContext("test", "https://privacy.invalid", "intent-synthetic");
            var store = new LocalPrivacyStore(root);
            var target = new OfficialFleetRealtimeTarget("synthetic", 7, "TEST",
                "scm-observed-membership-row-v1:" + (scenario == "inherited" ? "2" : "1"));
            var settings = new LocalPrivacySettings(true, new(PlayerSharedStateFields.None, false, false, []),
                new(PlayerSharedStateFields.None, false),
                Communities: scenario == "community"
                    ? [new("synthetic", DateTimeOffset.UnixEpoch.AddDays(1), PlayerSharedStateFields.Presence, false, true, [])] : [],
                OfficialFleet: scenario == "community" ? null : new(target,
                    scenario == "partial" ? PlayerSharedStateFields.Presence : CommunityRealtimeScope.SupportedFields,
                    "initial", Guid.NewGuid().ToString("N")));
            var saved = store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            var sends = 0;
            var input = new PrivacyPublicationInput(owner, 1, "Synthetic", true, "LIVE",
                new(new("connected", "US", "synthetic"), new("confirmed", "Test"), new("confirmed", "Test", "Test")),
                AppPresenceConfirmed: true);
            using var publisher = new PrivacyPublication(store, () => input,
                (_, _, _) => { sends++; return Task.CompletedTask; }, startTimer: false);
            var status = intent is null
                ? await publisher.ApplyAsync(owner, 1, saved.Revision, default, preservePause: true)
                : await publisher.ApplyAsync(owner, 1, saved.Revision, default, preservePause: true, firstOfficialDefault: intent.Value);
            Check(store.ReadPublicationMetadata(owner).ConsentVersion is null && sends == 0,
                scenario + ": omitted intent cannot consent or publish");
            Check(status.ErrorCode == "privacy_publication.consent_required", scenario + ": consent required receipt");
        }
    }

    internal static async Task ExplicitIntent()
    {
        foreach (var scenario in new[] { "default", "partial", "ranked", "community", "disabled", "paused", "invisible", "revoked" })
        {
            var root = Path.Combine(Path.GetTempPath(), "consent-b2-pair-" + Guid.NewGuid().ToString("N"));
            var owner = new BridgeAccountContext("test", "https://privacy.invalid", "intent-synthetic");
            var store = new LocalPrivacyStore(root);
            var target = new OfficialFleetRealtimeTarget("synthetic", 7, "TEST", "scm-observed-membership-row-v1:1");
            var settings = new LocalPrivacySettings(scenario != "disabled",
                new(PlayerSharedStateFields.None, false, false, []), new(PlayerSharedStateFields.None, false),
                Communities: scenario == "community"
                    ? [new("synthetic", DateTimeOffset.UnixEpoch.AddDays(1), PlayerSharedStateFields.Presence, false, true, [])] : [],
                OfficialFleet: new(target, scenario == "partial" ? PlayerSharedStateFields.Presence : CommunityRealtimeScope.SupportedFields,
                    "initial", Guid.NewGuid().ToString("N"), scenario == "ranked" ? 2 : null));
            var saved = store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            if (scenario == "paused") store.SetPublicationPaused(owner, saved.Revision, true, () => true);
            if (scenario == "revoked") store.SetPublicationConsent(owner, saved.Revision, false, () => true);
            var path = Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();
            var bytes = File.ReadAllBytes(path);
            var sends = 0;
            var input = new PrivacyPublicationInput(owner, 1, "", false, "LIVE",
                new(new("connected", "US", "synthetic"), new("confirmed", "Test"), new("confirmed", "Test", "Test")),
                AppPresenceConfirmed: true);
            using var pair = new PrivacyPublicationPair(store, () => input,
                (_, _, _) => { sends++; return Task.CompletedTask; }, startTimer: false,
                visibility: () => scenario == "invisible" ? PlayerPresenceVisibilityMode.Invisible : PlayerPresenceVisibilityMode.Online);
            // An intent on its own also retains the pause/visibility gates.
            var status = await pair.ApplyAsync(owner, 1, saved.Revision, default, firstOfficialDefault: true);
            var consent = store.ReadPublicationMetadata(owner).ConsentVersion;
            Check(sends == (scenario == "default" ? 1 : 0) &&
                consent == (scenario == "default" ? 1 : scenario == "revoked" ? 0 : (int?)null),
                scenario + ": explicit intent must meet all first-default gates in both lanes");
            if (scenario == "default")
                Check(status.State == "applied" && status.AppliedRevision == saved.Revision && status.ErrorCode is null,
                    "both lanes return the confirmed current revision");
            else
                Check(bytes.SequenceEqual(File.ReadAllBytes(path)), scenario + ": rejected intent leaves file unchanged");
        }
    }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
