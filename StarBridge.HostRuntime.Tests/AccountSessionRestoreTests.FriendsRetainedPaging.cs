using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task FriendsPagedRetainedDirectory()
    {
        using var transport = new PagedFriendsTransport { Large = true };
        using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
        await using var fixture = await RestoreDisplayFixture.Create(reader);
        fixture.Start("token");
        await fixture.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var request = BridgeEnvelope.Request("account.offlineData.read", "synthetic-retained-page-0", 0,
            new { schemaVersion = 1, kind = "friends", readId = fixture.ReadId, pagedResponse = true });
        var response = (await fixture.Native!.DispatchAsync(request)).Response;
        AssertEqual("ok", response.Status, "original pending restore can read the first retained page");
        var at = response.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset();
        var names = new HashSet<string>(StringComparer.Ordinal);
        var frames = new List<BridgeEnvelope>();
        var offset = 0;
        string? lastId = null;
        // Holding the original protected data file open without sharing proves
        // child pages do not repeatedly reopen/decrypt the full directory.
        using (var locked = new FileStream(Path.Combine(fixture.Root, "offline-account-v1", "friends-v1.bin"),
            FileMode.Open, FileAccess.Read, FileShare.None))
        {
            while (true)
            {
                frames.Add(response);
                AssertEqual("ok", response.Status, "every child remains readable without reopening the data file");
                AssertEqual<BridgeAccountContext?>(null, response.AccountContext, "a retained page never grants identity");
                AssertEqual(at, response.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset(), "all pages preserve the original synchronization time");
                AssertEqual(true, JsonSerializer.SerializeToUtf8Bytes(response, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes,
                    "every actual retained envelope respects the existing wire budget");
                var directory = response.Payload.GetProperty("directory");
                var page = directory.GetProperty("page");
                AssertEqual(offset, page.GetProperty("offset").GetInt32(), "retained offsets remain contiguous");
                lastId = page.GetProperty("snapshotId").GetString();
                foreach (var row in directory.GetProperty("incoming").EnumerateArray())
                {
                    AssertEqual(true, names.Add(row.GetProperty("callsign").GetString()!), "retained rows are not repeated");
                    AssertEqual(0, row.GetProperty("actions").GetArrayLength(), "retained pages contain no actions");
                    AssertEqual(false, row.TryGetProperty("targetRef", out _), "retained pages contain no command references");
                }
                var next = page.GetProperty("nextOffset");
                if (next.ValueKind == JsonValueKind.Null) break;
                offset = next.GetInt32();
                response = (await fixture.Native.DispatchAsync(BridgeEnvelope.Request("account.offlineData.read", "synthetic-retained-page-" + offset, 0,
                    new { schemaVersion = 1, kind = "friends", readId = fixture.ReadId, pagedResponse = true,
                        snapshotId = lastId, offset }))).Response;
            }
        }
        AssertEqual(PagedFriendsTransport.Count, names.Count, "all verified retained rows arrive");
        AssertEqual(1, transport.Reads, "only the original seed crosses friends HTTP");
        AssertEqual(false, fixture.Pending!.IsCompleted, "cached pages cannot finish authentication");
        fixture.Transport.Release.TrySetResult();
        var completed = await fixture.Pending.WaitAsync(TimeSpan.FromSeconds(5));
        SaveFriendsPagingWire("retained", new { prepared = fixture.Prepared, frames,
            completed = completed.Response, events = completed.Events });
        var retired = (await fixture.Native.DispatchAsync(BridgeEnvelope.Request("account.offlineData.read", "synthetic-retained-after-root", 0,
            new { schemaVersion = 1, kind = "friends", readId = fixture.ReadId, pagedResponse = true,
                snapshotId = lastId, offset = 0 }))).Response;
        AssertEqual(false, retired.Status == "ok", "the original readId retires after its root completes");
    }

    internal static async Task FriendsPagedRetainedFences()
    {
        foreach (var change in new[] { "readId", "generation", "context", "credential", "policy", "cancel" })
        {
            using var transport = new PagedFriendsTransport { Large = true };
            using var reader = new FriendsReader(new("https://synthetic-friends.invalid"), transport);
            await using var fixture = await RestoreDisplayFixture.Create(reader);
            fixture.Start("token");
            await fixture.Transport!.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            var first = (await fixture.Native!.DispatchAsync(BridgeEnvelope.Request("account.offlineData.read", "synthetic-retained-fence-first", 0,
                new { schemaVersion = 1, kind = "friends", readId = fixture.ReadId, pagedResponse = true }))).Response;
            AssertEqual("ok", first.Status, "prepare a genuine retained directory transfer");
            var page = first.Payload.GetProperty("directory").GetProperty("page");
            var store = new OfflineAccountStore(fixture.Root);
            using var publication = change == "policy" ? store.BeginFriendsRead(fixture.Owner, () => true) : null;
            if (change == "policy") AssertEqual(true, publication is not null, "the actual durable publication gate closes");
            if (change == "credential") fixture.Vault.SaveRefreshToken(fixture.Key, "synthetic-retained-new-credential");
            if (change == "cancel") fixture.Cancellation.Cancel();
            var next = BridgeEnvelope.Request("account.offlineData.read", "synthetic-retained-fence-next", change == "generation" ? 1 : 0,
                new { schemaVersion = 1, kind = "friends", readId = change == "readId" ? Guid.NewGuid().ToString("N") : fixture.ReadId,
                    pagedResponse = true, snapshotId = page.GetProperty("snapshotId").GetString(), offset = page.GetProperty("nextOffset").GetInt32() },
                change == "context" ? fixture.Owner : null);
            var denied = (await fixture.Runtime!.DispatchAsync(next)).Response;
            AssertEqual(false, denied.Status == "ok", "a later retained page rejects changed " + change);
            AssertEqual<BridgeAccountContext?>(null, denied.AccountContext, "refused retained data cannot expose an owner context");
            if (publication is not null)
            {
                store.CompleteFriendsRead(publication, OfflineFriendsReadOutcome.Unchanged, null, () => true);
                var replay = (await fixture.Native.DispatchAsync(next)).Response;
                AssertEqual(false, replay.Status == "ok", "reopening policy cannot revive a retired transfer; an explicit new first read is required");
            }
        }
    }
}
