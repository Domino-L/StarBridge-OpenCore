using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class OfficialSharingDefaultsTests
{
    internal static async Task Run()
    {
        await OfficialFleetAudienceTests.Run();
        Check(AccountBridgeRuntime.OfficialRealtimeEnabledByConfiguration(null), "absent flag enables protocol");
        Check(AccountBridgeRuntime.OfficialRealtimeEnabledByConfiguration("tRuE"), "case-insensitive true");
        foreach (var value in new[] { "false", "FALSE", "", "1", "invalid" })
            Check(!AccountBridgeRuntime.OfficialRealtimeEnabledByConfiguration(value), "explicit emergency off or malformed fail closed");

        // Isolated test root; no configured user data paths or network.
        var root = Path.Combine(Path.GetTempPath(), "sb-official-defaults-" + Guid.NewGuid().ToString("N"));
        var store = new LocalPrivacyStore(root);
        var owner = new BridgeAccountContext("test", "https://official.invalid", "synthetic");
        var target = new OfficialFleetRealtimeTarget("synthetic", 7, "TEST", "scm-observed-membership-row-v1:1");
        bool available = true;
        var bridge = new OfficialFleetRealtimePrivacyBridge(store, () => (owner, 1L),
            (_, _, _) => available ? Task.FromResult(new OfficialRealtimeContextWire(4, "officialFleet:7", target, null, "initial", true))
                : Task.FromException<OfficialRealtimeContextWire>(new AccountBridgeHostException("official_fleet.unavailable")), () => true);
        async Task<BridgeEnvelope> Read() => (await bridge.DispatchAsync(BridgeEnvelope.Request(
            "privacy.officialFleetRead", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, owner), default)).Response;
        var first = await Read();
        Check(first.Status == "ok" && first.Payload.GetProperty("fields").GetInt32() == 15 &&
            first.Payload.GetProperty("choiceRequired").GetBoolean(), "missing choice offers all-on draft");
        Check(store.Read(owner).Settings is null && !Directory.Exists(root), "read creates neither consent nor files");
        available = false;
        var noMembership = await Read();
        Check(noMembership.Payload.GetProperty("fields").GetInt32() == 0 &&
            !noMembership.Payload.GetProperty("choiceRequired").GetBoolean(), "no valid context cannot default or prompt");
        available = true;
        var previous = new LocalPrivacySettings(false, new(PlayerSharedStateFields.None, false, false, []),
            new(PlayerSharedStateFields.None, false), []);
        store.Save(owner, 0, Guid.NewGuid().ToString("N"), previous, () => true);
        Check((await Read()).Payload.GetProperty("fields").GetInt32() == 15, "community and manual pause do not determine fleet draft");
        foreach (var mask in new[] { 15, 5, 0 })
        {
            var scope = await Read();
            var saved = await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, contextRef = scope.Payload.GetProperty("contextRef").GetString(),
                    expectedRevision = store.Read(owner).Revision, operationId = Guid.NewGuid().ToString("N"), fields = mask }, owner), default);
            Check(saved.Response.Status == "ok", "explicit choice saves");
            var after = await Read();
            Check(after.Payload.GetProperty("fields").GetInt32() == mask &&
                !after.Payload.GetProperty("choiceRequired").GetBoolean(), "saved mask including all-off preserved");
            var settings = store.Read(owner).Settings!;
            Check(!settings.PublicationEnabled && settings.Room == previous.Room && settings.Fleet == previous.Fleet &&
                settings.Communities!.Length == 0, "ordinary settings and pause unchanged");
        }
        target = target with { MembershipEpoch = "scm-observed-membership-row-v1:2" };
        var changed = await Read();
        Check(changed.Payload.GetProperty("fields").GetInt32() == 0 &&
            !changed.Payload.GetProperty("choiceRequired").GetBoolean(), "existing choice is not reinterpreted as first use on changed membership");
        var revision = store.Read(owner).Revision;
        var enabled = store.Read(owner).Settings! with { PublicationEnabled = true };
        store.Save(owner, revision, Guid.NewGuid().ToString("N"), enabled, () => true);
        revision = store.Read(owner).Revision;
        // Real durable pause is independent of the visible PublicationEnabled bit.
        store.SetPublicationPaused(owner, revision, true, () => true);
        var sent = 0;
        var input = new PrivacyPublicationInput(owner, 1, "Synthetic", true, "LIVE",
            new(new("connected", "US", "synthetic"), new("confirmed", "Test"), new("confirmed", "Test", "Test")),
            AppPresenceConfirmed: true);
        var mode = PlayerPresenceVisibilityMode.Online;
        using var publisher = new PrivacyPublication(store, () => input, (_, _, _) => {
            sent++; return Task.CompletedTask;
        }, startTimer: false, visibility: () => mode);
        await publisher.ApplyAsync(owner, 1, revision, default, preservePause: true);
        Check(store.IsPublicationPaused(owner) && !store.HasPublicationConsent(owner) && sent == 0,
            "first choice cannot clear real persistent pause or publish another audience");
        store.SetPublicationPaused(owner, revision, false, () => true);
        await publisher.ApplyAsync(owner, 1, revision, default, preservePause: true);
        Check(store.IsPublicationRevoked(owner) && sent == 0, "new publisher preserves persisted revocation even with enabled settings");
        var visibilityStore = new LocalPrivacyStore(root + "-visibility");
        var visibilitySaved = visibilityStore.Save(owner, 0, Guid.NewGuid().ToString("N"), enabled with {
            OfficialFleet = enabled.OfficialFleet! with { Fields = PlayerSharedStateFields.Presence }
        }, () => true);
        mode = PlayerPresenceVisibilityMode.Invisible;
        using var visibilityPublisher = new PrivacyPublication(visibilityStore, () => input, (_, _, _) => {
            sent++; return Task.CompletedTask;
        }, startTimer: false, visibility: () => mode);
        Check(!visibilityStore.IsPublicationPaused(owner) && !visibilityStore.IsPublicationRevoked(owner), "independent invisible fixture is neither paused nor revoked");
        await visibilityPublisher.ApplyAsync(owner, 1, visibilitySaved.Revision, default, preservePause: true);
        Check(!visibilityStore.HasPublicationConsent(owner) && sent == 0,
            "invisible unconfirmed choice does not grant consent or publish");
        var observedStore = new LocalPrivacyStore(root + "-observed");
        var observedSaved = observedStore.Save(owner, 0, Guid.NewGuid().ToString("N"), visibilitySaved.Settings!, () => true);
        await observedStore.SetPublicationConsentAsync(owner, observedSaved.Revision, true, () => true, default);
        using var observedPublisher = new PrivacyPublication(observedStore, () => input, (_, _, _) => {
            sent++; return Task.CompletedTask;
        }, startTimer: false, visibility: () => PlayerPresenceVisibilityMode.Invisible);
        await observedPublisher.ApplyAsync(owner, 1, observedSaved.Revision, default, preservePause: true);
        Check(observedStore.IsPublicationPaused(owner) && sent == 0,
            "first-choice visibility read durably pauses previously consented sharing");
        var onlineStore = new LocalPrivacyStore(root + "-online");
        var onlineSaved = onlineStore.Save(owner, 0, Guid.NewGuid().ToString("N"), visibilitySaved.Settings!, () => true);
        using var onlinePublisher = new PrivacyPublication(onlineStore, () => input, (_, _, _) => {
            sent++; return Task.CompletedTask;
        }, startTimer: false, visibility: () => PlayerPresenceVisibilityMode.Online);
        await onlinePublisher.ApplyAsync(owner, 1, onlineSaved.Revision, default, preservePause: true);
        Check(onlineStore.HasPublicationConsent(owner) && sent > 0, "online fresh official-only choice can grant consent and publish");
        sent = 0;
        var unaskedStore = new LocalPrivacyStore(root + "-unasked");
        var unasked = unaskedStore.Save(owner, 0, Guid.NewGuid().ToString("N"), enabled with {
            Room = new(PlayerSharedStateFields.Presence, true)
        }, () => true);
        using var unaskedPublisher = new PrivacyPublication(unaskedStore, () => input, (_, _, _) => {
            sent++; return Task.CompletedTask;
        }, startTimer: false);
        var waiting = await unaskedPublisher.ApplyAsync(owner, 1, unasked.Revision, default, preservePause: true);
        Check(!unaskedStore.HasPublicationConsent(owner) && sent == 0 &&
            waiting.ErrorCode == "privacy_publication.existing_scope_confirmation_required",
            "official choice cannot grant never-confirmed ordinary scopes");
        var racingStore = new LocalPrivacyStore(root + "-race");
        var racing = racingStore.Save(owner, 0, Guid.NewGuid().ToString("N"), enabled with {
            Room = new(PlayerSharedStateFields.Presence, true)
        }, () => true);
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var raceSends = 0;
        using var racingPublisher = new PrivacyPublication(racingStore, () => input, async (_, _, _) => {
            raceSends++; entered.TrySetResult(); await release.Task;
        }, startTimer: false);
        var originalApply = racingPublisher.ApplyAsync(owner, 1, racing.Revision, default);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var queuedChoice = racingPublisher.ApplyAsync(owner, 1, racing.Revision, default, preservePause: true);
        racingStore.SetPublicationPaused(owner, racing.Revision, true, () => true);
        release.TrySetResult();
        await originalApply.WaitAsync(TimeSpan.FromSeconds(5));
        await queuedChoice.WaitAsync(TimeSpan.FromSeconds(5));
        Check(raceSends == 1 && racingStore.IsPublicationPaused(owner),
            "pause after request submission but before serialized apply is preserved");
        var file = Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();
        File.WriteAllText(file, "{}");
        var corrupt = await Read();
        Check(corrupt.Status == "error" && corrupt.Error?.Code == "privacy_local.read_failed", "corruption never falls back to all on");
        Console.WriteLine("PASS official sharing default/config/storage/explicit-choice regression");
        // Leave the tiny uniquely owned test fixture for diagnostics; no recursive cleanup.
    }
    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }
}
