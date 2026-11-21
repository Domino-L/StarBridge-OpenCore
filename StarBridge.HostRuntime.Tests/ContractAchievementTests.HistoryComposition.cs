using System.Reflection;
using StarBridge.Core.Events;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class ContractAchievementTests
{
    internal static async Task LocalHistoryProductionComposition()
    {
        var root = Root();
        try
        {
            await using var history = new LocalContractHistory(root, () => Ended.AddMinutes(1));
            using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"), () => Ended);
            journal.Load(); journal.Append("life", "synthetic", "旧事件"); await journal.FlushAsync();
            // No initial session, endpoint resolution or real vault. Any transport attempt is rejected in memory.
            using var handler = new RejectHistoryNetwork();
            var http = new ScmHttpClient(handler);
            var options = new ScmOAuthOptions("fixture", new("https://fixture.example.invalid/"),
                new("https://fixture.example.invalid/"), new("https://fixture.example.invalid/"),
                "fixture", "fixture", "profile.read", "/callback");
            using var host = new ScmAccountBridgeHost(new OAuthPkceClient(http, new NoVault(), options),
                new ScmProfileCacheStore(root), "fixture", () => null, deferBusinessStartup: true);
            using (var runtime = AccountBridgeRuntime.CreateAccountBusinessRuntime(host, root, journal,
                false, null, contractHistory: history))
            {
                object? Field(object target, string name) => target.GetType().GetField(name,
                    BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(target);
                var game = (GameLogRuntime)Field(runtime, "_gameLog")!;
                Require(ReferenceEquals(runtime.ContractHistory, history) && ReferenceEquals(Field(game, "_contractHistory"), history),
                    "actual account business factory passes the exact Native-owned history to GameLogRuntime");
                var tracker = (ContractRunTracker)Field(game, "_contractTracker")!;
                var events = Replay(deaths: false);
                var revision = history.ClearRevision;
                using var clear = new LocalEventClearDispatcher(journal, () => 2, history, () => Owner);
                var response = (await clear.DispatchAsync(BridgeEnvelope.Request(LocalEventClearDispatcher.RequestName,
                    Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1, confirmed = true }))).Response;
                Require(response.Status == "ok", "second production caller clears shared owner");
                tracker.Observe(Owner, HandleHash, events, () => true, true, historyRevision: revision);
                await history.FlushAsync();
                var reader = new LocalEventJournalReader(root, () => Ended.AddMinutes(1), () => history.DirectoryFor(Owner));
                Require(reader.Read().Entries.Count == 0, "production tracker cannot submit original read batch after dispatcher clear");
                var fresh = events.Where(e => e.Event.Type == FleetEventType.ContractEnded).Take(1)
                    .Select(e => (e.Event with { Contract = e.Event.Contract! with { MissionId = Guid.NewGuid().ToString() } }, true)).ToArray();
                tracker.Observe(Owner, HandleHash, fresh, () => true, true, historyRevision: history.ClearRevision);
                await history.FlushAsync();
                Require(reader.Read().Entries.Count == 1 && LocalEventJournalReader.FormatExport(reader.Read()).Contains("合约完成"),
                    "shared read/export owner sees only post-clear evidence");
                await game.DisposeAsync();
                await runtime.RetireNativeBusinessConsumersAsync();
            }
            // Runtime retirement borrows rather than closes the history owner.
            Require(await history.ClearAsync(Owner, () => true, default) == LocalJournalClearResult.Cleared,
                "account graph disposal preserves device-owned history lifetime");
        }
        finally { Directory.Delete(root, true); }
    }
    private sealed class RejectHistoryNetwork : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("Contract history composition must not use transport.");
    }
}