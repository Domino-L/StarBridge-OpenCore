using System.Net;
using System.Text;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task FriendsOnlineDisplay()
    {
        using var transport = new OnlineFriendsDisplayTransport();
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, directory, _) => {
            await using var native = new NativeAccountRuntimeBinding(runtime);
            var prepared = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
            native.EventReady += frame => { if (frame.Name == "friends.readDisplay") prepared.TrySetResult(frame); };
            transport.Hold = true;
            var request = BridgeEnvelope.Request("friends.read", "synthetic-online-directory", native.Generation,
                new { schemaVersion = 1, cachedDisplayProgress = true }, directory.AccountContext);
            var pending = native.DispatchAsync(request).AsTask();
            try
            {
                await Task.WhenAny(pending, transport.Entered.Task).WaitAsync(TimeSpan.FromSeconds(3));
                AssertEqual(true, prepared.Task.IsCompleted,
                    "ordinary signed-in directory must publish its local snapshot while original HTTP is still held");
                AssertEqual(false, pending.IsCompleted, "cache must not finish the actual friends read");
                var frame = await prepared.Task;
                AssertEqual(request.CorrelationId, frame.Payload.GetProperty("requestCorrelationId").GetString(), "progress belongs to this original read");
                AssertEqual(request.SessionGeneration, frame.SessionGeneration, "progress preserves original generation");
                AssertEqual<BridgeAccountContext?>(null, frame.AccountContext, "progress grants no account authority");
                var row = frame.Payload.GetProperty("directory").GetProperty("incoming")[0];
                AssertEqual("Stored Incoming", row.GetProperty("callsign").GetString(), "local snapshot precedes changed remote directory");
                AssertEqual(0, row.GetProperty("actions").GetArrayLength(), "cache has no commands");
                AssertEqual(false, row.TryGetProperty("targetRef", out var target) && target.ValueKind != System.Text.Json.JsonValueKind.Null,
                    "cache has no spent action references");
                AssertEqual(true, frame.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset() > DateTimeOffset.UnixEpoch,
                    "cache carries actual synchronization time");
            }
            finally { transport.Release.TrySetResult(); }
            var final = (await pending.WaitAsync(TimeSpan.FromSeconds(3))).Response;
            AssertEqual("ok", final.Status, "original friends response remains authoritative");
            AssertEqual("Updated Incoming", final.Payload.GetProperty("incoming")[0].GetProperty("callsign").GetString(), "fresh result replaces cached display");
            AssertEqual(2, transport.Reads, "progress sends no additional directory HTTP and never replays a write");
        });
    }

    internal static async Task FriendsOnlineDisplayBoundaries()
    {
        foreach (var boundary in new[] { "optOut", "search", "extra", "badFlag", "context", "generation", "noCache", "corrupt", "cancelBefore" })
        {
            using var transport = new OnlineFriendsDisplayTransport();
            using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
            await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, directory, root) => {
                if (boundary == "noCache") File.Delete(Path.Combine(root, "offline-account-v1", "friends-v1.bin"));
                if (boundary == "corrupt") File.WriteAllBytes(Path.Combine(root, "offline-account-v1", "friends-v1.bin"), [1, 2, 3]);
                await using var native = new NativeAccountRuntimeBinding(runtime);
                var frames = new List<BridgeEnvelope>();
                native.EventReady += frame => { if (frame.Name == "friends.readDisplay") frames.Add(frame); };
                transport.Hold = true;
                using var cancellation = new CancellationTokenSource();
                if (boundary == "cancelBefore") cancellation.Cancel();
                var payload = new Dictionary<string, object?> { ["schemaVersion"] = 1 };
                if (boundary != "optOut") payload["cachedDisplayProgress"] = boundary == "badFlag" ? "true" : true;
                if (boundary == "search") payload["query"] = "Pilot";
                if (boundary == "extra") payload["unrecognized"] = true;
                var request = BridgeEnvelope.Request("friends.read", "synthetic-online-boundary", boundary == "generation" ? native.Generation - 1 : native.Generation,
                    payload, boundary == "context" ? directory.AccountContext! with { Subject = "synthetic-other" } : directory.AccountContext);
                var pending = native.DispatchAsync(request, cancellation.Token).AsTask();
                try
                {
                    await Task.WhenAny(pending, transport.Entered.Task).WaitAsync(TimeSpan.FromSeconds(3));
                    AssertEqual(0, frames.Count, "no cached progress for " + boundary);
                }
                finally { transport.Release.TrySetResult(); }
                var result = (await pending.WaitAsync(TimeSpan.FromSeconds(3))).Response;
                AssertEqual(boundary is "optOut" or "noCache" or "corrupt", result.Status == "ok", "fresh read admission for " + boundary);
                AssertEqual(0, frames.Count, "late progress must not bypass boundary " + boundary);
            });
        }
    }

    internal static async Task FriendsOnlineDisplayOutcomes()
    {
        foreach (var outcome in new[] { "forbidden", "transient", "cancel" })
        {
            using var transport = new OnlineFriendsDisplayTransport();
            using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
            await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, directory, root) => {
                await using var native = new NativeAccountRuntimeBinding(runtime);
                var frames = 0;
                native.EventReady += frame => { if (frame.Name == "friends.readDisplay") frames++; };
                using var cancellation = new CancellationTokenSource();
                transport.Hold = true; transport.Outcome = outcome;
                var pending = native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-online-outcome", native.Generation,
                    new { schemaVersion = 1, cachedDisplayProgress = true }, directory.AccountContext), cancellation.Token).AsTask();
                await transport.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
                AssertEqual(1, frames, "original read publishes one readonly frame before its remote outcome");
                if (outcome == "cancel") cancellation.Cancel();
                transport.Release.TrySetResult();
                var final = (await pending.WaitAsync(TimeSpan.FromSeconds(3))).Response;
                AssertEqual(outcome == "cancel" ? "cancelled" : "error", final.Status, "original read outcome remains authoritative");
                if (outcome == "transient") AssertEqual(true, final.Error?.Retryable, "only known transient read remains recoverable");
                var saved = new StarBridge.HostRuntime.Account.OfflineAccountStore(root).ReadSelectedFriends(directory.AccountContext!, () => true);
                AssertEqual(outcome == "transient", saved is not null, "refusal and abandoned reads quarantine persisted data");
                AssertEqual(1, frames, "outcomes do not revive display or issue new progress");
                AssertEqual(2, transport.Reads, "no hidden directory replay");
            });
        }
    }

    internal static async Task FriendsOnlineDisplayLeaseEpoch()
    {
        using var transport = new OnlineFriendsDisplayTransport();
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, (runtime, directory, root) => {
            var store = new StarBridge.HostRuntime.Account.OfflineAccountStore(root);
            using var first = store.BeginFriendsRead(directory.AccountContext!, () => true, captureDisplay: true)!;
            AssertEqual("Stored Incoming", first.Display!.Directory.Incoming.Single().Callsign, "original writer admission captures the previous committed display");
            AssertEqual(true, store.IsFriendsDisplayCurrent(first, () => true), "capture belongs to this active policy epoch");
            AssertEqual<StarBridge.HostRuntime.Account.OfflineFriendsDisplay?>(null, store.ReadSelectedFriends(directory.AccountContext!, () => true),
                "public retained reads remain closed while original directory IO is pending");
            using var second = store.BeginFriendsRead(directory.AccountContext!, () => true, captureDisplay: true)!;
            AssertEqual<StarBridge.HostRuntime.Account.OfflineFriendsDisplay?>(null, second.Display, "another pending reader cannot expose an unconfirmed candidate");
            store.CompleteFriendsRead(second, StarBridge.HostRuntime.Account.OfflineFriendsReadOutcome.Rejected, null, () => true);
            AssertEqual(false, store.IsFriendsDisplayCurrent(first, () => true), "known refusal invalidates captured progress before it is published");
            first.Dispose();
            AssertEqual<StarBridge.HostRuntime.Account.OfflineFriendsDisplay?>(null, first.Display, "retirement releases captured display memory");
            return Task.CompletedTask;
        });
    }

    private sealed class OnlineFriendsDisplayTransport : HttpMessageHandler
    {
        internal int Reads;
        internal bool Hold;
        internal string? Outcome;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (request.Method != HttpMethod.Get) throw new Exception("Display read must never write");
            Interlocked.Increment(ref Reads);
            var name = "Stored Incoming";
            if (Hold)
            {
                Entered.TrySetResult();
                await Release.Task.WaitAsync(token);
                if (Outcome == "forbidden") return new(HttpStatusCode.Forbidden);
                if (Outcome == "transient") throw new HttpRequestException("Synthetic directory outage");
                name = "Updated Incoming";
            }
            return new(HttpStatusCode.OK) { Content = new StringContent(
                "{\"friends\":[],\"incomingRequests\":[{\"user\":{\"accountId\":\"synthetic-private-peer\",\"callsign\":\"" + name +
                "\",\"gameId\":\"\",\"relationshipState\":\"incoming\"},\"relationshipUpdatedAt\":\"2026-10-17T00:00:00Z\"}],\"outgoingRequests\":[],\"blockedUsers\":[],\"refreshedAt\":\"2026-10-17T00:00:00Z\"}", Encoding.UTF8, "application/json") };
        }
    }
}
