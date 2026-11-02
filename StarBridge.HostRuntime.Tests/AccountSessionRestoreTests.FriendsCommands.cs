using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static Task FriendsSnapshotAcceptedCommand() => FriendsSnapshotCommand("accepted");
    internal static Task FriendsSnapshotUnknownCommand() => FriendsSnapshotCommand("unknown");
    internal static Task FriendsSnapshotRejectedCommand() => FriendsSnapshotCommand("rejected");

    internal static async Task FriendsSnapshotCommandGuard()
    {
        using var transport = new FriendCommandSnapshotTransport("accepted");
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var f = await RestoreDisplayFixture.Create(reader, async (runtime, directory, root) => {
            // Lock the policy before the command's durable admission can close.
            var file = Path.Combine(root, "offline-account-v1", "friends-policy-v1.bin");
            using var held = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read);
            var target = directory.Payload.GetProperty("incoming")[0].GetProperty("targetRef").GetString();
            var result = (await runtime.DispatchAsync(BridgeEnvelope.Request("friends.execute", "synthetic-blocked-command", runtime.Generation,
                new { schemaVersion = 1, action = "reject", targetRef = target }, directory.AccountContext))).Response;
            AssertEqual("ok", result.Status, "pre-POST guard failure is a classified no-write response");
            AssertEqual("rejected", result.Payload.GetProperty("status").GetString(), "guard failure must not report uncertain POST outcome");
            AssertEqual("refreshRequired", result.Payload.GetProperty("error").GetString(), "guard failure requires a fresh explicit action");
        });
        AssertEqual(0, transport.Writes, "unprotected command must not reach POST");
    }

    private static async Task FriendsSnapshotCommand(string outcome)
    {
        using var transport = new FriendCommandSnapshotTransport(outcome);
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var f = await RestoreDisplayFixture.Create(reader, async (runtime, directory, _) => {
            var target = directory.Payload.GetProperty("incoming")[0].GetProperty("targetRef").GetString();
            var command = BridgeEnvelope.Request("friends.execute", "synthetic-friends-command", runtime.Generation,
                new { schemaVersion = 1, action = "reject", targetRef = target }, directory.AccountContext);
            var result = (await runtime.DispatchAsync(command)).Response;
            AssertEqual("ok", result.Status, "command response envelope");
            AssertEqual(outcome, result.Payload.GetProperty("status").GetString(), "actual command outcome must be exercised");
        });
        AssertEqual(1, transport.Writes, "cache maintenance must never replay a POST");
        f.Start("token");
        await f.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var response = (await f.Native!.DispatchAsync(BridgeEnvelope.Request("account.offlineData.read", "synthetic-after-command", 0,
            new { schemaVersion = 1, kind = "friends", readId = f.ReadId }))).Response;
        if (outcome == "unknown")
            AssertEqual(false, response.Status == "ok", "uncertain write must not leave the previous directory eligible");
        else
        {
            AssertEqual("ok", response.Status, "classified command preserves a coherent read-only snapshot");
            AssertEqual(outcome == "accepted" ? 0 : 1,
                response.Payload.GetProperty("directory").GetProperty("incoming").GetArrayLength(),
                "confirmed mutation updates cache while definite no-write keeps prior directory");
        }
    }

    private sealed class FriendCommandSnapshotTransport(string outcome) : HttpMessageHandler
    {
        private bool _removed;
        internal int Writes;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (request.Method == HttpMethod.Post)
            {
                Writes++;
                if (outcome == "rejected") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests));
                _removed = true;
                if (outcome == "unknown") throw new IOException("Synthetic lost POST response");
            }
            else if (request.Method != HttpMethod.Get) throw new Exception("Unexpected method");
            object[] incoming = _removed ? [] : [new {
                user = new { accountId = "synthetic-command-peer", callsign = "Stored Incoming", gameId = "", relationshipState = "incoming" },
                relationshipUpdatedAt = DateTimeOffset.UtcNow }];
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                friends = Array.Empty<object>(), incomingRequests = incoming, outgoingRequests = Array.Empty<object>(),
                blockedUsers = Array.Empty<object>(), refreshedAt = DateTimeOffset.UtcNow }) });
        }
    }
}
