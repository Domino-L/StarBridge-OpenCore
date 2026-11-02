using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class LocalStatisticsChoiceBridgeTests
{
    private static BridgeEnvelope Request(string name, long generation = 1, object? payload = null) =>
        BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, payload ?? new { schemaVersion = 1 });
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task<string> Read(IBridgeRequestDispatcher d, long gen = 1) =>
        (await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest, gen))).Response.Payload.GetProperty("choiceKey").GetString()!;
    private static ValueTask<BridgeDispatchBatch> Choose(IBridgeRequestDispatcher d, string key, bool allowed, long gen = 1) =>
        d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ConfirmRequest, gen, new { schemaVersion = 1, choiceKey = key, allowed }));
    internal static async Task Run()
    {
        await Projection(); await Choices(); await Invalid(); await Stale(); await FailedSave(); await FinalGuard(); await Closed(); await Composition();
        await ReplacedOwner(); await ReplacementDuringConfirmation();
    }
    private static async Task Projection()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        var reply = (await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest))).Response;
        Check(reply.Status == "ok" && reply.AccountContext is null && reply.Payload.GetProperty("consent").GetString() == "unknown" &&
            reply.Payload.GetProperty("state").GetString() == "choiceRequired", "identity never grants consent");
        var raw = reply.Payload.GetRawText();
        Check(new[] { "profileId", "sourceKey", "Handle", "revision", "localSettingsReady", f.Root, f.Profile, f.Key }
            .All(value => !raw.Contains(value, StringComparison.OrdinalIgnoreCase)), "exact safe projection");
        Check(!Directory.Exists(f.StatisticsDirectory) && f.AccountReads == 0, "read is not a write, account read or recording grant");
        Console.WriteLine("PASS local statistics bridge: actual read is safe, unknown and read-only");
    }
    private static async Task Choices()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        var key = await Read(d); var allowed = (await Choose(d, key, true)).Response;
        Check(allowed.Payload.GetProperty("state").GetString() == "saved" && f.Saved.Consent == GameplayRecordingConsent.Allowed &&
            !allowed.Payload.GetProperty("recording").GetBoolean() && f.Saved.Seconds == 0, "saved permission alone does not enable listening or backfill");
        Check((await Choose(d, key, true)).Response.Status == "error", "key is consumed");
        f.EnableListening(); f.Tick(0); f.Tick(5); key = await Read(d); f.Tick(5);
        // The one real sampler may advance totals while this same consent remains observed.
        var declined = (await Choose(d, key, false)).Response;
        Check(declined.Payload.GetProperty("consent").GetString() == "declined" && f.Saved.Seconds == 10, "decline preserves ongoing saved totals");
        f.Tick(20); f.Reopen(); Check(f.Stats.Current.Consent == "declined" && f.Saved.Seconds == 10, "reopen preserves explicit choice");
        Check(f.Clock.Timers.Count(t => !t.Disposed) == 1 && f.AccountReads == 0, "one actual sampler, no account borrowing");
        Console.WriteLine("PASS local statistics bridge: explicit allow/decline persist without sharing, backfill or duplicate timer");
    }
    private static async Task Invalid()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        foreach (var json in new[] { "{}", "[]", "{\"schemaVersion\":true}", "{\"schemaVersion\":1,\"schemaVersion\":1}",
            "{\"schemaVersion\":1,\"path\":\"private\"}" })
        {
            using var doc = JsonDocument.Parse(json);
            Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest, payload: doc.RootElement))).Response.Status == "error", "strict read");
        }
        foreach (var payload in new object[] { new { schemaVersion = 1, choiceKey = "bad", allowed = true },
            new { schemaVersion = 1, choiceKey = await Read(d), allowed = "true" }, new { schemaVersion = 1, choiceKey = await Read(d), allowed = true, Handle = "fixture" } })
            Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ConfirmRequest, payload: payload))).Response.Status == "error", "strict confirm");
        Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest) with { AccountContext = new("test", "test", "test") })).Response.Status == "error", "no account authority");
        Check(!Directory.Exists(f.StatisticsDirectory), "malformed input never writes");
        Console.WriteLine("PASS local statistics bridge: strict fields, types, key and device-only context");
    }
    private static async Task Stale()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); long generation = 1;
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => generation);
        var key = await Read(d); generation = 2;
        Check((await Choose(d, key, true, 2)).Response.Status == "error", "new request generation cannot borrow previous observation");
        key = await Read(d, 2); f.Stats.ApplyConsent(f.Key, false);
        Check((await Choose(d, key, true, 2)).Response.Status == "error", "another explicit choice invalidates old observation");
        key = await Read(d, 2); var bytes = f.Bytes(f.Profile);
        f.WriteIdentity("Another-Pilot", "200"); f.EnableListening(); f.Tick(5); f.ConfirmCurrent();
        Check((await Choose(d, key, true, 2)).Response.Status == "error" && f.Stats.Current.Consent == "unknown", "old profile cannot grant new profile consent");
        Check(bytes.SequenceEqual(f.Bytes(f.Identities.Read().Profiles.Single(p => p.Handle == "Pilot-Example").Id)), "old file preserved");
        f.Mode = (false, f.Mode.Generation + 1);
        Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest, 2))).Response.Payload.GetProperty("state").GetString() == "inactive", "online/inactive local owner cannot grant local choice");
        Console.WriteLine("PASS local statistics bridge: Host generation, profile, mode and consent changes revoke observation");
    }
    private static async Task FailedSave()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        var key = await Read(d);
        using (f.Storage.Open(f.Profile, () => true))
        {
            var reply = (await Choose(d, key, true)).Response;
            Check(reply.Status == "ok" && reply.Payload.GetProperty("state").GetString() == "retryRequired" &&
                reply.Payload.GetProperty("consent").GetString() == "unknown" && !reply.Payload.GetProperty("recording").GetBoolean(), "failed allow is not durable permission");
        }
        f.EnableListening(); f.Tick(5); f.Tick(5);
        Check(f.Saved.Consent == GameplayRecordingConsent.Unknown, "released writer does not auto-retry");
        key = await Read(d); await Choose(d, key, false);
        var bytes = f.Bytes(f.Profile); File.WriteAllBytes(f.PathFor(f.Profile), [1, 2, 3]);
        var bad = (await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest))).Response;
        Check(bad.Status == "error" && f.Bytes(f.Profile).SequenceEqual(new byte[] { 1, 2, 3 }) &&
            !bad.Error!.Message.Contains(f.Root), "damaged original preserved and no private errors");
        File.WriteAllBytes(f.PathFor(f.Profile), bytes);
        Console.WriteLine("PASS local statistics bridge: failed and damaged saves require fresh explicit choice, preserve originals");
    }
    private static async Task Closed()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        var key = await Read(d); using var cts = new CancellationTokenSource(); cts.Cancel();
        Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ConfirmRequest, payload: new { schemaVersion = 1, choiceKey = key, allowed = true }), cts.Token)).Response.Status == "cancelled", "pre-cancel no write");
        d.Dispose(); Check((await Choose(d, key, true)).Response.Status == "error" && !Directory.Exists(f.StatisticsDirectory), "disposed bridge sealed");
        var read = f.Stats.ReadConsent(() => true); await f.Stats.RetireAsync();
        try { f.Stats.ConfirmConsent(read.ChoiceKey!, true, () => true); throw new InvalidOperationException("retired consent"); }
        catch (LocalFirstUseException) { }
        Console.WriteLine("PASS local statistics bridge: cancellation and actual retirement cannot authorize late choice");
    }
    private static Task FinalGuard()
    {
        using var f = new LocalGameplayTimeTests.Fixture();
        var observed = f.Stats.ReadConsent(() => true); var checks = 0;
        try { f.Stats.ConfirmConsent(observed.ChoiceKey!, true, () => ++checks < 4); throw new InvalidOperationException("scope changed"); }
        catch (LocalFirstUseException) { }
        Check(f.Saved == LocalGameplayTimeSaved.Empty && !f.Stats.Current.Recording, "final Host guard prevents durable consent");
        observed = f.Stats.ReadConsent(() => true); checks = 0;
        using var token = new CancellationTokenSource();
        bool Current() { if (++checks == 3) token.Cancel(); return true; }
        try { f.Stats.ConfirmConsent(observed.ChoiceKey!, true, Current, token.Token); throw new InvalidOperationException("cancelled consent"); }
        catch (OperationCanceledException) { }
        Check(f.Saved == LocalGameplayTimeSaved.Empty && !f.Stats.Current.Recording, "cancellation during actual commit guard does not save or resume");
        Console.WriteLine("PASS local statistics bridge: actual final commit guard and cancellation prevent unconfirmed recording");
        return Task.CompletedTask;
    }
    private static async Task Composition()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); var fallback = new NeverDispatch();
        using var d = new CompositeBridgeDispatcher(fallback, fallback, fallback,
            firstUseStatistics: new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1));
        Check((await Read(d)).Length == 32, "actual borrowed statistics owner routes");
        foreach (var name in new[] { LocalStatisticsChoiceBridgeDispatcher.ReadRequest, LocalStatisticsChoiceBridgeDispatcher.ConfirmRequest })
            Check(!BridgeRequestPolicy.RequiresAccountContext(name), "only exact device exception");
        Check(BridgeRequestPolicy.RequiresAccountContext("onboarding.localStatistics.reset") && BridgeRequestPolicy.RequiresAccountContext("friends.read"), "no prefix/business expansion");
        Check((await d.DispatchAsync(Request("onboarding.localStatistics.reset"))).Response.Status == "error" && fallback.Calls == 0, "unknown command blocked");
        Console.WriteLine("PASS local statistics bridge: composition and exact request policy do not open whole onboarding");
    }
    private static async Task ReplacedOwner()
    {
        using var first = new LocalGameplayTimeTests.Fixture();
        using var second = new LocalGameplayTimeTests.Fixture();
        LocalGameplayTimeRuntime? current = first.Stats;
        var fallback = new NeverDispatch();
        using var bridge = new CompositeBridgeDispatcher(fallback, fallback, fallback,
            firstUseStatistics: new LocalStatisticsChoiceBridgeDispatcher(() => current, () => 1));
        var oldKey = await Read(bridge);
        await first.Stats.RetireAsync();
        current = null;
        Check((await bridge.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest))).Response.Error?.Code ==
            "firstUse.context_changed", "recovery gap cannot report a live statistics owner");
        current = second.Stats;
        Check((await Choose(bridge, oldKey, true)).Response.Status == "error", "retired owner's choice cannot authorize replacement");
        Check(!Directory.Exists(first.StatisticsDirectory) && !Directory.Exists(second.StatisticsDirectory), "replacement is not consent");
        var newKey = await Read(bridge);
        Check(newKey != oldKey && (await Choose(bridge, newKey, false)).Response.Status == "ok" &&
            second.Saved.Consent == GameplayRecordingConsent.Declined && !Directory.Exists(first.StatisticsDirectory),
            "same composed route reaches only replacement after fresh explicit choice");
        Check(first.AccountReads == 0 && second.AccountReads == 0 && fallback.Calls == 0,
            "device replacement never borrows account dispatch");
        Console.WriteLine("PASS local statistics bridge: stable composed route follows replacement, rejects old consent and recovery gap");
    }
    private static async Task ReplacementDuringConfirmation()
    {
        using var first = new LocalGameplayTimeTests.Fixture();
        using var second = new LocalGameplayTimeTests.Fixture();
        LocalGameplayTimeRuntime? current = first.Stats;
        var checks = 0; var replace = false;
        using var bridge = new LocalStatisticsChoiceBridgeDispatcher(() => current, () =>
        {
            if (replace && ++checks == 2) current = second.Stats;
            return 1;
        });
        var key = await Read(bridge);
        replace = true;
        Check((await Choose(bridge, key, true)).Response.Status == "error" &&
            !Directory.Exists(first.StatisticsDirectory) && !Directory.Exists(second.StatisticsDirectory),
            "owner changed during validation cannot save to either profile");
        replace = false;
        var fresh = await Read(bridge);
        bridge.Dispose();
        Check((await Choose(bridge, fresh, true)).Response.Status == "error" && !Directory.Exists(second.StatisticsDirectory),
            "disposing stable bridge seals future replacement observations");
        Console.WriteLine("PASS local statistics bridge: owner change during confirmation and disposal cannot grant recording");
    }
    private sealed class NeverDispatch : IBridgeRequestDispatcher
    {
        internal int Calls;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        { Calls++; throw new InvalidOperationException("Unexpected business dispatch"); }
        public void Dispose() { }
    }
}
