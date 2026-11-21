using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class FirstDefaultAdmissionObservationTests
{
    internal static Task InvisibleObservation() => ApplyWhileWaiting("invisible");
    internal static Task PauseObservation() => ApplyWhileWaiting("pause");
    internal static Task CurrentVisibility() => ApplyWhileWaiting("visibility");
    internal static Task NoObservation() => ApplyWhileWaiting("none");
    internal static Task UnrelatedObservation() => ApplyWhileWaiting("unrelated");

    private static async Task ApplyWhileWaiting(string scenario)
    {
        var root = Path.Combine(Path.GetTempPath(), "consent-b3-" + Guid.NewGuid().ToString("N"));
        var owner = new BridgeAccountContext("test", "https://privacy.invalid", "admission-synthetic");
        var store = new LocalPrivacyStore(root);
        var target = new OfficialFleetRealtimeTarget("synthetic", 7, "TEST", "scm-observed-membership-row-v1:1");
        var settings = new LocalPrivacySettings(true, new(PlayerSharedStateFields.None, false, false, []),
            new(PlayerSharedStateFields.None, false),
            OfficialFleet: new(target, CommunityRealtimeScope.SupportedFields, "initial", Guid.NewGuid().ToString("N")));
        var saved = store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
        var path = Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();
        var before = File.ReadAllBytes(path);
        var input = new PrivacyPublicationInput(owner, 1, "Synthetic", true, "LIVE",
            new(new("connected", "US", "synthetic"), new("confirmed", "Test"), new("confirmed", "Test", "Test")),
            AppPresenceConfirmed: true);
        var visibility = new PublicationVisibilitySnapshot(owner, 1, "test", 1, PlayerPresenceVisibilityMode.Online, null);
        var sends = 0;
        using var publisher = new PrivacyPublication(store, () => input,
            (_, _, _) => { sends++; return Task.CompletedTask; }, startTimer: false,
            visibilitySnapshot: () => visibility);
        using var admission = await store.PositiveAdmission.EnterAsync(default);
        // Apply executes synchronously through its prechecks to the held admission.
        // No timer, sleeps or publication wake can provide a second observation.
        var applying = publisher.ApplyAsync(owner, 1, saved.Revision, default, firstOfficialDefault: true);
        Check(!applying.IsCompleted, scenario + ": apply must wait at admission");
        Check(store.ReadPublicationMetadata(owner).ConsentVersion is null && sends == 0,
            scenario + ": admission wait has neither consent nor sends");

        switch (scenario)
        {
            case "invisible":
                publisher.ObserveVisibility(visibility with { Mode = PlayerPresenceVisibilityMode.Invisible, Observation = null });
                break;
            case "pause":
                // A definite pause observation remains authoritative even if the
                // current visibility producer still reports Online.
                publisher.ObserveVisibility(visibility with { Observation = 3 });
                break;
            case "visibility":
                visibility = visibility with { Mode = PlayerPresenceVisibilityMode.Invisible, Observation = null };
                break;
            case "unrelated":
                publisher.ObserveVisibility(visibility with { Generation = 2, Observation = 3 });
                publisher.ObserveVisibility(visibility with {
                    Owner = owner with { Subject = "other-synthetic" }, Observation = 3 });
                break;
        }
        admission.Dispose();
        var status = await applying.WaitAsync(TimeSpan.FromSeconds(5));
        var reopened = new LocalPrivacyStore(root);
        var metadata = reopened.ReadPublicationMetadata(owner);
        var blocked = scenario is "invisible" or "pause" or "visibility";
        Check(metadata.ConsentVersion == (blocked ? (int?)null : 1), scenario + ": consent after reopening");
        Check(!metadata.PublicationPaused && reopened.Read(owner).Revision == saved.Revision,
            scenario + ": pause metadata and policy revision are unchanged");
        Check(sends == (blocked ? 0 : 1), scenario + ": send count");
        Check(status.State == (blocked ? "withdrawn" : "applied") &&
            status.AppliedRevision == saved.Revision && status.ErrorCode is null,
            scenario + ": existing status receipt");
        if (blocked)
            Check(before.SequenceEqual(File.ReadAllBytes(path)), scenario + ": no consent write or policy mutation");
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
