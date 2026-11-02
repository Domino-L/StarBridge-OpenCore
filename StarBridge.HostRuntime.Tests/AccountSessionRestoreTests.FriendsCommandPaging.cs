using System.Net;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task FriendsCommandPagingFrame()
    {
        using var transport = new CommandPagingTransport();
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, seeded, dataRoot) => {
            await using var native = new NativeAccountRuntimeBinding(runtime);
            var root = (await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", "synthetic-command-pages-root", native.Generation,
                new { schemaVersion = 1 }))).Response;
            var initial = (await native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-command-pages-initial", native.Generation,
                new { schemaVersion = 1, pagedResponse = true }, seeded.AccountContext))).Response;
            var initialFrames = new List<BridgeEnvelope> { initial };
            var page = initial.Payload.GetProperty("page");
            while (page.GetProperty("nextOffset").ValueKind != JsonValueKind.Null)
            {
                var next = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-initial-child-" + initialFrames.Count,
                    native.Generation, new { schemaVersion = 1, snapshotId = page.GetProperty("snapshotId").GetString(),
                        offset = page.GetProperty("nextOffset").GetInt32() }, seeded.AccountContext))).Response;
                AssertEqual("ok", next.Status, "prepare initial actual paged rows");
                initialFrames.Add(next); page = next.Payload.GetProperty("page");
            }
            var target = initial.Payload.GetProperty("incoming")[0].GetProperty("targetRef").GetString();
            var payload = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["action"] = "reject", ["targetRef"] = target };
            // Negotiate exactly as an updated client does: the original Host
            // still accepts its legacy write, exposing the real size defect.
            if (AccountBridgeRuntime.AdvertisedCapabilities.Contains("friends.commandPages")) payload["pagedResponse"] = true;
            var response = (await native.DispatchAsync(BridgeEnvelope.Request("friends.execute", "synthetic-command-pages-write", native.Generation,
                payload, seeded.AccountContext))).Response;
            AssertEqual("ok", response.Status, "actual command acknowledgement envelope");
            AssertEqual("accepted", response.Payload.GetProperty("status").GetString(), "the POST is confirmed, not rejected or unknown");
            AssertEqual(1, transport.Writes, "the confirmed operation reaches POST exactly once");
            AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(response, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                "confirmed command acknowledgement must fit the real frame budget");
            AssertEqual("paged", response.Payload.GetProperty("directoryState").GetString(), "confirmation and directory transport are separate states");
            var command = response;
            var frames = new List<BridgeEnvelope>();
            var directory = response.Payload.GetProperty("directory");
            var callsigns = new HashSet<string>(StringComparer.Ordinal);
            while (true)
            {
                frames.Add(response);
                AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(response, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                    "every result directory page fits the unchanged frame budget");
                foreach (var row in directory.GetProperty("incoming").EnumerateArray())
                    AssertEqual(true, callsigns.Add(row.GetProperty("callsign").GetString()!), "result rows never repeat");
                page = directory.GetProperty("page");
                if (page.GetProperty("nextOffset").ValueKind == JsonValueKind.Null) break;
                response = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-command-result-child-" + frames.Count,
                    native.Generation, new { schemaVersion = 1, snapshotId = page.GetProperty("snapshotId").GetString(),
                        offset = page.GetProperty("nextOffset").GetInt32() }, seeded.AccountContext))).Response;
                AssertEqual("ok", response.Status, "result pages survive completion of the original command");
                directory = response.Payload;
            }
            AssertEqual(CommandPagingTransport.Count - 1, callsigns.Count, "the confirmed directory contains every remaining request");
            AssertEqual(3, transport.Reads, "only seed, initial read and command preflight reach GET; result pages reuse the POST body");
            AssertEqual(1, transport.Writes, "result paging never replays the operation");
            SaveFriendsPagingWire("command", new { root, initialFrames, command, frames, reads = transport.Reads, writes = transport.Writes });
            var replay = (await native.DispatchAsync(BridgeEnvelope.Request("friends.execute", "synthetic-command-replayed-target", native.Generation,
                payload, seeded.AccountContext))).Response;
            AssertEqual("rejected", replay.Payload.GetProperty("status").GetString(), "the original consumed target cannot be reused");
            AssertEqual("targetChanged", replay.Payload.GetProperty("error").GetString(), "replay requires an explicit new directory");
            AssertEqual(1, transport.Writes, "a consumed reference never causes another POST");
            var retired = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-command-retired-result", native.Generation,
                new { schemaVersion = 1, snapshotId = command.Payload.GetProperty("directory").GetProperty("page").GetProperty("snapshotId").GetString(), offset = 0 },
                seeded.AccountContext))).Response;
            AssertEqual("friends.snapshot_changed", retired.Error?.Code, "a later command retires the previous result directory too");
        });
    }

    internal static async Task FriendsCommandPagingCompatibility()
    {
        foreach (var (count, flag) in new (int, bool?)[] { (2, null), (2, false), (1400, null), (1400, false) })
        {
            using var transport = new CommandPagingTransport(count);
            using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
            await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, seeded, dataRoot) => {
                await using var native = new NativeAccountRuntimeBinding(runtime);
                var root = (await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", "synthetic-command-compat-root", native.Generation,
                    new { schemaVersion = 1 }))).Response;
                var initialFrames = await CommandPagingInitial(native, seeded.AccountContext!);
                var payload = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["action"] = "reject",
                    ["targetRef"] = initialFrames[0].Payload.GetProperty("incoming")[0].GetProperty("targetRef").GetString() };
                if (flag.HasValue) payload["pagedResponse"] = flag.Value;
                var command = (await native.DispatchAsync(BridgeEnvelope.Request("friends.execute", "synthetic-command-compat", native.Generation,
                    payload, seeded.AccountContext))).Response;
                AssertEqual("accepted", command.Payload.GetProperty("status").GetString(), "legacy request still receives the actual write confirmation");
                AssertEqual(1, transport.Writes, "compatibility never replays a POST");
                AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(command, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                    "even a legacy request must not close the pipe with an oversized acknowledgement");
                if (count == 2)
                {
                    AssertEqual(false, command.Payload.TryGetProperty("directoryState", out _), "small legacy result keeps the exact original shape");
                    AssertEqual(false, command.Payload.GetProperty("directory").TryGetProperty("page", out _), "small legacy directory is not silently paged");
                    AssertEqual(1, command.Payload.GetProperty("directory").GetProperty("incoming").GetArrayLength(), "legacy result is complete");
                }
                else
                {
                    AssertEqual("unavailable", command.Payload.GetProperty("directoryState").GetString(), "legacy large result reports a separate presentation failure");
                    AssertEqual("refreshRequired", command.Payload.GetProperty("directorySyncError").GetString(), "stable directory failure category");
                    AssertEqual(false, command.Payload.TryGetProperty("directory", out _), "never send a truncated directory disguised as complete");
                }
                if (!flag.HasValue) SaveFriendsPagingWire(count == 2 ? "small-command" : "legacy-command",
                    new { root, initialFrames, command, reads = transport.Reads, writes = transport.Writes });
            });
        }
    }

    internal static async Task FriendsCommandPagingValidation()
    {
        using var transport = new CommandPagingTransport(2);
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, seeded, dataRoot) => {
            var target = seeded.Payload.GetProperty("incoming")[0].GetProperty("targetRef").GetString();
            foreach (var invalid in new object?[] { null, "true", 1, new { value = true } })
            {
                // Use an explicit JsonElement so the bridge's null-property
                // omission cannot accidentally turn this into a valid write.
                var body = JsonSerializer.SerializeToElement(new { schemaVersion = 1, action = "reject", targetRef = target, pagedResponse = invalid });
                var result = (await runtime.DispatchAsync(BridgeEnvelope.Request("friends.execute", "synthetic-command-invalid-" + Guid.NewGuid().ToString("N"), runtime.Generation,
                    body, seeded.AccountContext))).Response;
                AssertEqual("friends.invalid_request", result.Error?.Code, "pagedResponse is a boolean-only bridge option");
            }
        });
        AssertEqual(0, transport.Writes, "invalid paging options must never reach POST");
    }

    internal static async Task FriendsCommandPagingResultFences()
    {
        foreach (var change in new[] { "context", "generation", "binding" })
        {
            using var transport = new CommandPagingTransport();
            using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
            await using var fixture = await RestoreDisplayFixture.Create(reader, async (runtime, seeded, dataRoot) => {
                await using var native = new NativeAccountRuntimeBinding(runtime);
                var target = seeded.Payload.GetProperty("incoming")[0].GetProperty("targetRef").GetString();
                var command = (await native.DispatchAsync(BridgeEnvelope.Request("friends.execute", "synthetic-result-fence-command", native.Generation,
                    new { schemaVersion = 1, action = "reject", targetRef = target, pagedResponse = true }, seeded.AccountContext))).Response;
                AssertEqual("accepted", command.Payload.GetProperty("status").GetString(), "prepare a confirmed result snapshot");
                var page = command.Payload.GetProperty("directory").GetProperty("page");
                var owner = change == "context" ? seeded.AccountContext! with { Subject = "synthetic-other-owner" } : seeded.AccountContext!;
                var generation = native.Generation + (change == "generation" ? 1 : 0);
                if (change == "binding") await native.DisposeAsync();
                var response = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", "synthetic-result-fence-child", generation,
                    new { schemaVersion = 1, snapshotId = page.GetProperty("snapshotId").GetString(), offset = page.GetProperty("nextOffset").GetInt32() }, owner))).Response;
                AssertEqual(false, response.Status == "ok", "a completed command cannot authorize a result page after changed " + change);
                AssertEqual(1, transport.Writes, "scope failure never repeats the operation");
            });
        }
    }

    private static async Task<List<BridgeEnvelope>> CommandPagingInitial(NativeAccountRuntimeBinding native, BridgeAccountContext owner)
    {
        var first = (await native.DispatchAsync(BridgeEnvelope.Request("friends.read", "synthetic-command-initial-" + Guid.NewGuid().ToString("N"), native.Generation,
            new { schemaVersion = 1, pagedResponse = true }, owner))).Response;
        var frames = new List<BridgeEnvelope> { first };
        var page = first.Payload.GetProperty("page");
        while (page.GetProperty("nextOffset").ValueKind != JsonValueKind.Null)
        {
            var next = (await native.DispatchAsync(BridgeEnvelope.Request("friends.readPage", Guid.NewGuid().ToString("N"), native.Generation,
                new { schemaVersion = 1, snapshotId = page.GetProperty("snapshotId").GetString(), offset = page.GetProperty("nextOffset").GetInt32() }, owner))).Response;
            AssertEqual("ok", next.Status, "initial result page");
            frames.Add(next); page = next.Payload.GetProperty("page");
        }
        return frames;
    }

    private sealed class CommandPagingTransport(int count = CommandPagingTransport.Count) : HttpMessageHandler
    {
        internal const int Count = 1400;
        internal int Reads, Writes;
        private bool _removed;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (request.Method == HttpMethod.Post) { Writes++; _removed = true; }
            else if (request.Method == HttpMethod.Get) Reads++;
            else throw new InvalidOperationException("Unexpected synthetic method");
            var start = _removed ? 1 : 0;
            var rows = Enumerable.Range(start, count - start).Select(index => new {
                user = new { accountId = "synthetic-command-page-peer-" + index, callsign = new string('舰', 256) + index,
                    gameId = "", relationshipState = "incoming" }, relationshipUpdatedAt = DateTimeOffset.UtcNow
            });
            var json = JsonSerializer.Serialize(new { friends = Array.Empty<object>(), incomingRequests = rows,
                outgoingRequests = Array.Empty<object>(), blockedUsers = Array.Empty<object>(), refreshedAt = DateTimeOffset.UtcNow },
                new JsonSerializerOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json, Encoding.UTF8, "application/json") });
        }
    }
}
