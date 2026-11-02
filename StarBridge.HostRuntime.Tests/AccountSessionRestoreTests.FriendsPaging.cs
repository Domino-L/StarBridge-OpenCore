using System.Net;
using System.Text.Encodings.Web;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task FriendsPagedDirectory()
    {
        using var transport = new PagedFriendsTransport();
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, directory, dataRoot) => {
            await using var native = new NativeAccountRuntimeBinding(runtime);
            var root = (await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", "synthetic-paging-root", native.Generation,
                new { schemaVersion = 1 }))).Response;
            var frames = new List<BridgeEnvelope>();
            transport.Large = true;
            var legacy = (await native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-large-original", native.Generation,
                new { schemaVersion = 1 }, directory.AccountContext))).Response;
            AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(legacy, BridgeProtocol.JsonOptions).Length > BridgeProtocol.MaximumFrameBytes,
                "actual valid upstream directory exposes the original single-frame capacity gap");
            var response = (await native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-large-paged", native.Generation,
                new { schemaVersion = 1, pagedResponse = true }, directory.AccountContext))).Response;
            var names = new HashSet<string>(StringComparer.Ordinal);
            var offset = 0;
            while (true)
            {
                frames.Add(response);
                AssertEqual("ok", response.Status, "large directory must arrive in bounded pages, not become an invalid request");
                AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(response, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                    "every real response respects the unchanged wire budget");
                var page = response.Payload.GetProperty("page");
                AssertEqual(true, page.TryGetProperty("nextOffset", out _), "terminal metadata includes an explicit null rather than an omitted field");
                AssertEqual(offset, page.GetProperty("offset").GetInt32(), "page offset is contiguous");
                foreach (var row in response.Payload.GetProperty("incoming").EnumerateArray())
                    AssertEqual(true, names.Add(row.GetProperty("callsign").GetString()!), "no repeated directory rows");
                if (!page.TryGetProperty("nextOffset", out var next) || next.ValueKind == JsonValueKind.Null) break;
                offset = next.GetInt32();
                response = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-large-page-" + offset, native.Generation,
                    new { schemaVersion = 1, snapshotId = page.GetProperty("snapshotId").GetString(), offset }, directory.AccountContext))).Response;
            }
            AssertEqual(PagedFriendsTransport.Count, names.Count, "all original rows arrive without truncation");
            AssertEqual(3, transport.Reads, "pages reuse the original authorized read; only seed, legacy demonstration and one paged GET reach HTTP");
            SaveFriendsPagingWire("fresh", new { root, frames });
        });
    }

    internal static async Task FriendsPagedCommandRetirement()
    {
        using var transport = new PagedFriendsTransport();
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, directory, dataRoot) => {
            await using var native = new NativeAccountRuntimeBinding(runtime);
            transport.Large = true;
            var first = (await native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-first-page", native.Generation,
                new { schemaVersion = 1, pagedResponse = true }, directory.AccountContext))).Response;
            AssertEqual("ok", first.Status, "prepare a real authorized page snapshot");
            var page = first.Payload.GetProperty("page");
            transport.HoldNext = true;
            var earlierRead = native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-held-pages", native.Generation,
                new { schemaVersion = 1, pagedResponse = true }, directory.AccountContext)).AsTask();
            await transport.Arrived.Task.WaitAsync(TimeSpan.FromSeconds(5));
            // Even a definitively rejected command is an ordering boundary.
            // It queues behind the actual directory IO and never sends a POST.
            var command = native.DispatchAsync(BridgeEnvelope.Request("friends.execute", "synthetic-page-boundary", native.Generation,
                new { schemaVersion = 1, action = "invalid", targetRef = Guid.NewGuid().ToString("N") }, directory.AccountContext)).AsTask();
            try
            {
                var oldPage = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-old-page", native.Generation,
                    new { schemaVersion = 1, snapshotId = page.GetProperty("snapshotId").GetString(), offset = page.GetProperty("nextOffset").GetInt32() },
                    directory.AccountContext))).Response;
                AssertEqual("friends.snapshot_changed", oldPage.Error?.Code, "command admission retires the already opened snapshot");
            }
            finally { transport.Release.TrySetResult(); }
            var stale = (await earlierRead.WaitAsync(TimeSpan.FromSeconds(5))).Response;
            AssertEqual("friends.snapshot_changed", stale.Error?.Code, "a directory started before the command cannot publish a replacement snapshot afterward");
            AssertEqual("error", (await command.WaitAsync(TimeSpan.FromSeconds(5))).Response.Status, "synthetic command is rejected without a write");
            var refreshed = (await native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-after-command", native.Generation,
                new { schemaVersion = 1, pagedResponse = true }, directory.AccountContext))).Response;
            AssertEqual("ok", refreshed.Status, "an explicit new read can create a current snapshot after the ordering boundary");
        });
    }

    internal static Task FriendsPagedStoreBoundaries()
    {
        var clock = new FriendsPageClock();
        var store = new FriendsDirectoryPageStore(clock);
        var owner = new BridgeAccountContext("synthetic", "synthetic", "synthetic");
        var live = true;
        var directory = BridgePayload.From(new FriendsView(null, clock.Now,
            [], [new("Synthetic", "", "incoming", null, clock.Now)], [], [], []));
        string Open() => store.Open(directory, owner, 3, "fresh", () => live).GetProperty("page").GetProperty("snapshotId").GetString()!;
        void Reject(Action action, string code)
        {
            try { action(); }
            catch (StarBridge.HostRuntime.Account.AccountBridgeHostException error)
            { AssertEqual(code, error.Code, "stable rejected page category"); return; }
            throw new InvalidOperationException("Expected the page request to be rejected.");
        }
        var id = Open();
        Reject(() => store.Read(id, 0, owner with { Subject = "other" }, 3, "fresh"), "friends.snapshot_changed");
        Reject(() => store.Read(id, 0, owner, 4, "fresh"), "friends.snapshot_changed");
        Reject(() => store.Read(id, 0, owner, 3, "retained"), "friends.snapshot_changed");
        Reject(() => store.Read(id, -1, owner, 3, "fresh"), "friends.invalid_request");
        Reject(() => store.Read(id, 2, owner, 3, "fresh"), "friends.invalid_request");
        for (var i = 0; i < 4; i++) Open();
        Reject(() => store.Read(id, 0, owner, 3, "fresh"), "friends.snapshot_changed");
        id = Open();
        clock.Now += TimeSpan.FromMinutes(1);
        Reject(() => store.Read(id, 0, owner, 3, "fresh"), "friends.snapshot_changed");
        id = Open(); live = false;
        Reject(() => store.Read(id, 0, owner, 3, "fresh"), "friends.snapshot_changed");
        Reject(() => Open(), "friends.snapshot_changed");
        live = true; id = Open(); store.Clear();
        Reject(() => store.Read(id, 0, owner, 3, "fresh"), "friends.snapshot_changed");
        id = Open();
        var huge = BridgePayload.From(new FriendsView(null, clock.Now,
            [], [new(new string('X', BridgeProtocol.MaximumFrameBytes), "", "incoming", null, clock.Now)], [], [], []));
        Reject(() => store.Open(huge, owner, 3, "fresh", () => true), "friends.snapshot_too_large");
        AssertEqual(1, store.Read(id, 0, owner, 3, "fresh").GetProperty("incoming").GetArrayLength(),
            "a refused unpageable directory leaves the prior valid snapshot usable");
        return Task.CompletedTask;
    }

    private sealed class FriendsPageClock : TimeProvider
    {
        internal DateTimeOffset Now = new(2026, 10, 17, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }

    internal static async Task FriendsPagedOnlineDisplay()
    {
        using var transport = new PagedFriendsTransport { Large = true };
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, directory, dataRoot) => {
            await using var native = new NativeAccountRuntimeBinding(runtime);
            BridgeEnvelope? progress = null;
            var root = (await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", "synthetic-cache-paging-root", native.Generation,
                new { schemaVersion = 1 }))).Response;
            var cachedFrames = new List<BridgeEnvelope>();
            native.EventReady += frame => { if (frame.Name == "friends.readDisplay") progress = frame; };
            transport.HoldNext = true;
            const string correlation = "synthetic-cache-paging";
            var pending = native.DispatchAsync(BridgeEnvelope.Request("friends.read", correlation, native.Generation,
                new { schemaVersion = 1, cachedDisplayProgress = true, pagedResponse = true }, directory.AccountContext)).AsTask();
            try
            {
                await transport.Arrived.Task.WaitAsync(TimeSpan.FromSeconds(5));
                AssertEqual(true, progress is not null, "large cached display must arrive while its actual HTTP is still pending");
                AssertEqual(false, pending.IsCompleted, "cached pages are independent of the original HTTP response");
                AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(progress, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                    "the first optional event respects the unchanged frame budget");
                var cached = progress!.Payload.GetProperty("directory");
                var count = 0;
                while (true)
                {
                    foreach (var row in cached.GetProperty("incoming").EnumerateArray())
                    {
                        count++;
                        AssertEqual(0, row.GetProperty("actions").GetArrayLength(), "cached rows never carry actions");
                        AssertEqual(false, row.TryGetProperty("targetRef", out _), "cached pages carry no command reference");
                    }
                    var page = cached.GetProperty("page");
                    if (page.GetProperty("nextOffset").ValueKind == JsonValueKind.Null) break;
                    var response = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-cache-child-" + count,
                        native.Generation, new { schemaVersion = 1, snapshotId = page.GetProperty("snapshotId").GetString(),
                            offset = page.GetProperty("nextOffset").GetInt32(), displayRequestId = correlation }, directory.AccountContext))).Response;
                    AssertEqual("ok", response.Status, "cached child page remains in its original pending request scope");
                    AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(response, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                        "every cached child respects the same real wire budget");
                    cachedFrames.Add(response);
                    cached = response.Payload;
                }
                AssertEqual(PagedFriendsTransport.Count, count, "all retained rows arrive privately without truncation");
                AssertEqual(2, transport.Reads, "cache pages perform no additional directory HTTP");
                var last = cached.GetProperty("page");
                var wrong = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-cache-wrong-origin", native.Generation,
                    new { schemaVersion = 1, snapshotId = last.GetProperty("snapshotId").GetString(), offset = 0,
                        displayRequestId = "another-original-request" }, directory.AccountContext))).Response;
                AssertEqual("friends.snapshot_changed", wrong.Error?.Code, "display pages cannot borrow another original request");
                transport.Release.TrySetResult();
                var completed = (await pending.WaitAsync(TimeSpan.FromSeconds(5))).Response;
                AssertEqual("ok", completed.Status, "actual fresh directory completes independently");
                var freshFrames = new List<BridgeEnvelope> { completed };
                var freshPage = completed.Payload.GetProperty("page");
                while (freshPage.GetProperty("nextOffset").ValueKind != JsonValueKind.Null)
                {
                    var nextFresh = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-online-fresh-" + freshFrames.Count,
                        native.Generation, new { schemaVersion = 1, snapshotId = freshPage.GetProperty("snapshotId").GetString(),
                            offset = freshPage.GetProperty("nextOffset").GetInt32() }, directory.AccountContext))).Response;
                    AssertEqual("ok", nextFresh.Status, "fresh follow-up pages are independent from retired cache authority");
                    freshFrames.Add(nextFresh);
                    freshPage = nextFresh.Payload.GetProperty("page");
                }
                SaveFriendsPagingWire("online", new { root, prepared = progress, cachedFrames, freshFrames });
                var retired = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-cache-after-original", native.Generation,
                    new { schemaVersion = 1, snapshotId = last.GetProperty("snapshotId").GetString(), offset = 0,
                        displayRequestId = correlation }, directory.AccountContext))).Response;
                AssertEqual("friends.snapshot_changed", retired.Error?.Code, "cached transfer authority ends with the original read");
            }
            finally { transport.Release.TrySetResult(); await pending; }
        });
    }

    private static void SaveFriendsPagingWire(string suffix, object value)
    {
        var prefix = Environment.GetEnvironmentVariable("STARBRIDGE_FRIENDS_PAGING_WIRE_PREFIX");
        if (string.IsNullOrWhiteSpace(prefix)) return;
        var path = Path.GetFullPath(prefix + "-" + suffix + ".json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
        JsonSerializer.Serialize(stream, value, BridgeProtocol.JsonOptions);
    }

    private sealed class PagedFriendsTransport : HttpMessageHandler
    {
        internal const int Count = 1400;
        internal bool Large;
        internal int Reads;
        internal bool HoldNext;
        internal readonly TaskCompletionSource Arrived = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (request.Method != HttpMethod.Get) throw new Exception("Paging must not write");
            Reads++;
            if (HoldNext)
            {
                HoldNext = false;
                Arrived.TrySetResult();
                await Release.Task.WaitAsync(token);
            }
            var rows = Enumerable.Range(0, Large ? Count : 1).Select(index => new {
                user = new { accountId = "synthetic-page-peer-" + index,
                    callsign = new string('舰', 256) + index, gameId = "", relationshipState = "incoming" },
                relationshipUpdatedAt = DateTimeOffset.UtcNow
            }).ToArray();
            var json = JsonSerializer.Serialize(new { friends = Array.Empty<object>(), incomingRequests = rows,
                outgoingRequests = Array.Empty<object>(), blockedUsers = Array.Empty<object>(), refreshedAt = DateTimeOffset.UtcNow },
                new JsonSerializerOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json") };
        }
    }
}
