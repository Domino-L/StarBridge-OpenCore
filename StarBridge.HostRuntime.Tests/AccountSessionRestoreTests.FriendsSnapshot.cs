using System.Net;
using System.Text;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task FriendsSnapshotColdRead()
    {
        using var transport = new SnapshotFriendsTransport();
        using var friends = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var f = await RestoreDisplayFixture.Create(friends);
        AssertEqual(true, transport.Reads > 0, "warm seed must cross the real friends transport and Host route");
        f.Start("token");
        await f.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var request = BridgeEnvelope.Request("account.offlineData.read", "synthetic-cached-friends", 0,
            new { schemaVersion = 1, readId = f.ReadId, kind = "friends" });
        var result = (await f.Native!.DispatchAsync(request)).Response;
        AssertEqual("ok", result.Status, "previously read friends must be locally readable before original authentication completes");
        AssertEqual(false, f.Pending!.IsCompleted, "cached friends cannot complete the held authentication");
        AssertEqual(0, result.Payload.GetProperty("directory").GetProperty("friends").GetArrayLength(),
            "a confirmed empty directory must replace an older snapshot too");
        AssertEqual(true, result.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset() > DateTimeOffset.UnixEpoch,
            "cache carries its actual synchronization time");
        AssertEqual(false, result.AccountContext is not null, "cached directory never grants an account context");
        var incoming = result.Payload.GetProperty("directory").GetProperty("incoming").EnumerateArray().Single();
        AssertEqual("Stored Incoming", incoming.GetProperty("callsign").GetString(), "actual private directory display survives restart");
        AssertEqual(0, incoming.GetProperty("actions").GetArrayLength(), "cache contains no command actions");
        AssertEqual(true, !incoming.TryGetProperty("targetRef", out var reference) || reference.ValueKind == System.Text.Json.JsonValueKind.Null,
            "cache cannot carry the warm native command lease");
    }

    internal static async Task FriendsSnapshotReadBoundaries()
    {
        foreach (var change in new[] { "context", "generation", "extra", "credential", "cancel", "corrupt" })
        {
            using var transport = new SnapshotFriendsTransport();
            using var friends = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
            await using var f = await RestoreDisplayFixture.Create(friends);
            f.Start("token");
            await f.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var payload = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["readId"] = f.ReadId, ["kind"] = "friends" };
            if (change == "extra") payload["unknown"] = true;
            else if (change == "credential") f.Vault.SaveRefreshToken(f.Key, "synthetic-replacement");
            else if (change == "cancel") f.Cancellation.Cancel();
            else if (change == "corrupt") File.WriteAllBytes(Path.Combine(f.Root, "offline-account-v1", "friends-v1.bin"), [1, 2, 3]);
            var request = BridgeEnvelope.Request("account.offlineData.read", "synthetic-friends-boundary", change == "generation" ? 1 : 0,
                payload, change == "context" ? f.Owner : null);
            var response = (await f.Runtime!.DispatchAsync(request)).Response;
            AssertEqual(false, response.Status == "ok", "friends retained read must reject " + change);
        }
    }

    private sealed class SnapshotFriendsTransport : HttpMessageHandler
    {
        internal int Reads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (request.Method != HttpMethod.Get) throw new Exception("Friends cache seed attempted a write");
            Reads++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent("{\"friends\":[],\"incomingRequests\":[{\"user\":{\"accountId\":\"synthetic-private-peer\",\"callsign\":\"Stored Incoming\",\"gameId\":\"HiddenPeer\",\"relationshipState\":\"incoming\"},\"relationshipUpdatedAt\":\"2026-10-17T00:00:00Z\"}],\"outgoingRequests\":[],\"blockedUsers\":[],\"refreshedAt\":\"2026-10-17T00:00:00Z\"}", Encoding.UTF8, "application/json")
            });
        }
    }
}
