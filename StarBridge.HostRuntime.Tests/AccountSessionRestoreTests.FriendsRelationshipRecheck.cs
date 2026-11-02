using System.Diagnostics;
using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task FriendsRelationshipRecheckFailures()
    {
        // Exercise the actual SCM Host route and durable cache completion, without
        // depending on opt-in diagnostics. Only an initial outage may retain data.
        foreach (var failure in new[] { "initial503", "recheck503", "recheck429",
            "recheckTransport", "recheckTimeout", "recheckUnknown", "recheckDeadline", "recheckCancel" })
            await VerifyRelationshipRecheckFailure(failure,
                failure == "initial503" ? "friends.read_transient" : "friends.read_unavailable", true);
        await VerifyRelationshipRecheckFailure("recheckClassified", "friends.synthetic_rejection", true);
        await VerifyRelationshipRecheckFailure("recheckNonRetryableTransient", "friends.read_transient", false);
    }

    internal static Task FriendsRelationshipRecheck401() =>
        VerifyRelationshipRecheckFailure("recheck401", "friends.identity_unavailable", false);

    internal static Task FriendsRelationshipRecheck403() =>
        VerifyRelationshipRecheckFailure("recheck403", "friends.forbidden", false);

    internal static Task FriendsRelationshipRecheckDataInvalid() =>
        VerifyRelationshipRecheckFailure("recheckInvalid", "friends.data_invalid", false);

    internal static Task FriendsRelationshipRecheckPageRetirement() =>
        VerifyRelationshipRecheckFailure("recheck503", "friends.read_unavailable", true, verifyPages: true);

    private static async Task VerifyRelationshipRecheckFailure(string failure, string expectedCode,
        bool retryable, bool verifyPages = true)
    {
        using var cancellation = new CancellationTokenSource();
        using var transport = new RelationshipRecheckTransport(cancellation);
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid/"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, directory, root) => {
            var store = new OfflineAccountStore(root);
            AssertEqual(1, store.ReadSelectedFriends(directory.AccountContext!, () => true)!.Directory.Friends.Length,
                "seed a real previously verified friend before " + failure);
            var fresh = (await runtime.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-recheck-fresh",
                runtime.Generation, new { schemaVersion = 1, pagedResponse = true }, directory.AccountContext))).Response;
            AssertEqual("ok", fresh.Status, "successful reads still create fresh pages");
            var snapshotId = fresh.Payload.GetProperty("page").GetProperty("snapshotId").GetString();
            async Task<BridgeEnvelope> ReadPage() => (await runtime.DispatchAsync(BridgeEnvelope.Request(
                "friends.readPage", "synthetic-recheck-page", runtime.Generation,
                new { schemaVersion = 1, snapshotId, offset = 0 }, directory.AccountContext))).Response;
            var before = await ReadPage();
            AssertEqual("ok", before.Status, "fresh page is readable before the failed read");
            AssertEqual(1, before.Payload.GetProperty("friends").GetArrayLength(), "fresh page contains the old friend");
            transport.Failure = failure;
            transport.Reads = 0;
            var started = Stopwatch.GetTimestamp();
            var response = (await runtime.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-recheck-failure",
                runtime.Generation, new { schemaVersion = 1 }, directory.AccountContext), cancellation.Token)).Response;
            var initial = failure == "initial503";
            AssertEqual(initial ? 1 : 2, transport.Reads, "failure occurs at the intended directory phase");
            AssertEqual(failure == "recheckCancel" ? "cancelled" : "error", response.Status,
                "relationship safety never accepts a failed read");
            if (failure != "recheckCancel")
            {
                AssertEqual(expectedCode, response.Error?.Code, failure + " preserves classified rejection semantics");
                AssertEqual(retryable, response.Error?.Retryable, failure + " preserves retryability");
            }
            if (failure == "recheckDeadline")
            {
                AssertEqual(true, transport.DeadlineCancelled, "real request token deadline interrupts the recheck");
                AssertEqual(false, cancellation.IsCancellationRequested, "internal deadline leaves caller token active");
                AssertEqual(true, Stopwatch.GetElapsedTime(started) >= TimeSpan.FromSeconds(11),
                    "production twelve-second deadline actually elapsed");
            }
            AssertEqual(initial, store.ReadSelectedFriends(directory.AccountContext!, () => true) is not null,
                "an unconfirmed removed or blocked friend cannot survive a failed relationship recheck");
            if (verifyPages && failure != "recheckCancel" || initial)
            {
                var after = await ReadPage();
                AssertEqual(initial ? "ok" : "error", after.Status,
                    "only initial transient outages preserve existing fresh pages");
                if (!initial) AssertEqual("friends.snapshot_changed", after.Error?.Code,
                    "rejected read retires the old snapshot");
                else AssertEqual(1, after.Payload.GetProperty("friends").GetArrayLength(),
                    "initial transient retains the original page rows");
                AssertEqual(initial ? 1 : 2, transport.Reads, "reading pages never repeats directory HTTP");
            }
        });
    }

    private sealed class RelationshipRecheckTransport(CancellationTokenSource cancellation) : HttpMessageHandler
    {
        internal string? Failure;
        internal int Reads;
        internal bool DeadlineCancelled;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            AssertEqual(HttpMethod.Get, request.Method, "relationship verification never writes");
            AssertEqual("/api/friends", request.RequestUri!.AbsolutePath, "legacy friends need no SCM identity request");
            Reads++;
            if (Failure == "initial503" || Failure is not null && Reads == 2)
            {
                switch (Failure)
                {
                    case "recheckTransport": throw new HttpRequestException("Synthetic recheck outage");
                    case "recheckTimeout": throw new OperationCanceledException("Synthetic recheck deadline");
                    case "recheckUnknown": throw new InvalidOperationException("Synthetic unknown recheck failure");
                    case "recheckClassified": throw new AccountBridgeHostException("friends.synthetic_rejection", true);
                    case "recheckNonRetryableTransient": throw new AccountBridgeHostException("friends.read_transient", false);
                    case "recheckInvalid": return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{invalid-json") };
                    case "recheckDeadline":
                        try { await Task.Delay(Timeout.InfiniteTimeSpan, token); }
                        catch (OperationCanceledException) when (token.IsCancellationRequested)
                        { DeadlineCancelled = true; throw; }
                        throw new InvalidOperationException("Deadline must cancel the pending recheck");
                    case "recheckCancel": cancellation.Cancel(); token.ThrowIfCancellationRequested(); break;
                }
                var status = Failure switch {
                    "recheck429" => HttpStatusCode.TooManyRequests,
                    "recheck401" => HttpStatusCode.Unauthorized,
                    "recheck403" => HttpStatusCode.Forbidden,
                    _ => HttpStatusCode.ServiceUnavailable
                };
                return new HttpResponseMessage(status);
            }
            return new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new ByteArrayContent(FriendsReaderTests.Directory(FriendsReaderTests.User("synthetic-legacy-peer")))
            };
        }
    }
}
