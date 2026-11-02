using System.Collections;
using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityMemberReferenceTests
{
    internal static async Task WorkspaceLease()
    {
        using var handler = new Handler();
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var page = await client.ReadAsync("fixture", new("mine", "", null, null), "scope", default);
        var targetRef = page.Items[0].TargetRef;
        var query = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef, query = "", offset = 0 });
        var first = Reference(await client.ReadWorkspaceAsync("fixture", query, "scope", default));
        ExpireLeases(client);
        var media = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef, kind = "avatar", memberRef = first, offset = 0 });
        var calls = handler.Calls;
        await Error(() => client.ReadMediaAsync("fixture", media, "scope", default));
        var memberQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef, memberRef = first });
        await Error(() => client.ReadMemberRemovalAsync("fixture", memberQuery, "scope", () => { }, default));
        await Error(() => client.ReadMemberRoleAsync("fixture", memberQuery, "scope", () => { }, default));
        await Error(() => client.ReadOwnershipTransferAsync("fixture", memberQuery, "scope", () => { }, default));
        foreach (var kind in new[] { "role", "remove", "transfer", "exit" })
            await Error(() => client.ReadWpfS2GovernanceAsync("fixture", memberQuery, "scope", kind, () => { }, default));
        try { client.ResolveVisitorProfileTarget(memberQuery, "scope", null); throw new InvalidOperationException("Expired visitor reference accepted"); }
        catch (AccountBridgeHostException error) when (error.Code == "communities.refreshRequired") { }
        Check(client.OverlayPreferenceKey(first, "scope") is null, "Expired overlay identity must be rejected");
        Check(handler.Calls == calls, "Expired member consumers must reject before any HTTP request");
        var second = Reference(await client.ReadWorkspaceAsync("fixture", query, "scope", default));
        Check(first == second, "CX-L13: workspace memberRef changed after the five-minute authorization lease expired");
        await client.ReadMediaAsync("fixture", media, "scope", default);
    }

    internal static async Task OtherIssuers()
    {
        using var f = new Fixture();
        var reference = Reference(await f.Workspace());
        foreach (var source in new[] { "ships", "announcements", "chat" })
        {
            for (var i = 0; i < 2; i++)
            {
                ExpireLeases(f.Client);
                await Error(() => f.Media(reference));
                var issued = await f.Source(source);
                Check(issued == reference, source + " must reuse the workspace identity after lease expiry");
                await f.Media(reference);
            }
            Check(Reference(await f.Workspace()) == reference, source + " must agree with the next workspace read");
        }
    }

    internal static async Task RejectedReadsDoNotRenew()
    {
        using var f = new Fixture();
        var reference = Reference(await f.Workspace());
        foreach (var source in new[] { "workspace", "ships", "announcements", "chat" })
        {
            ExpireLeases(f.Client);
            f.Handler.Invalid = true;
            await Error(() => source == "workspace" ? f.Workspace() : ReadSource(), "communities.dataInvalid");
            await Error(() => f.Media(reference));
            f.Handler.Invalid = false;
            Check(Reference(await f.Workspace()) == reference, "A rejected read cannot replace the retained identity");
            async Task<object> ReadSource() => await f.Source(source);
        }
    }

    internal static async Task Isolation()
    {
        using var f = new Fixture();
        var a = Reference(await f.Workspace());
        var otherPage = await f.Client.ReadAsync("fixture", new("mine", "", null, null), "other", default);
        var otherTarget = otherPage.Items[0].TargetRef;
        var other = Reference(await f.Client.ReadWorkspaceAsync("fixture", Query(otherTarget), "other", default));
        var b = Reference(await f.Client.ReadWorkspaceAsync("fixture", Query(f.B), "scope", default));
        Check(a != b && a != other && b != other, "Organization code and account generation must both separate identities");
        var calls = f.Handler.Calls;
        await Error(() => f.Media(a, f.B));
        await Error(() => f.Media(a, otherTarget, "other"));
        await Error(() => f.Media(other));
        Check(f.Handler.Calls == calls, "Cross-organization and cross-scope member references must never reach HTTP");
        ExpireLeases(f.Client);
        Check(Reference(await f.Workspace()) == a, "A new scope must never supply its mapping to an older scope");
    }

    internal static async Task LeaveClears()
    {
        using var f = new Fixture();
        var first = Reference(await f.Workspace());
        var other = Reference(await f.Client.ReadWorkspaceAsync("fixture", Query(f.B), "scope", default));
        var result = await f.Client.ExecuteAsync("fixture", JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, action = "leave", targetRef = f.A }), "scope", () => { }, default);
        Check(result.Status == "accepted" && Retained(f.Client, "account:member-one", "A", "scope", false) is null,
            "A confirmed modern leave clears the retained member mapping");
        Check(Retained(f.Client, "account:member-one", "B", "scope", false) == other, "Leaving preserves other organizations");
        f.Handler.Left = false;
        var page = await f.Client.ReadAsync("fixture", new("mine", "", null, null), "scope", default);
        var freshTarget = page.Items[0].TargetRef;
        Check(Reference(await f.Client.ReadWorkspaceAsync("fixture", Query(freshTarget), "scope", default)) != first,
            "Rejoining cannot reuse the identity invalidated by leaving");
        await Error(() => f.Media(first, freshTarget));
    }

    internal static async Task Retention()
    {
        using var f = new Fixture();
        var now = DateTimeOffset.UtcNow;
        f.Client.MemberReferenceUtcNow = () => now;
        var first = Reference(await f.Workspace());
        now += TimeSpan.FromHours(23);
        ExpireLeases(f.Client);
        Check(Reference(await f.Workspace()) == first, "Identity survives expired lease within 24 hours");
        now += TimeSpan.FromHours(23);
        Check(Reference(await f.Workspace()) == first, "Successful reads renew the sliding identity retention");
        ExpireLeases(f.Client);
        f.Handler.Invalid = true;
        now += TimeSpan.FromHours(23);
        await Error(() => f.Workspace(), "communities.dataInvalid");
        f.Handler.Invalid = false;
        now += TimeSpan.FromHours(1);
        Check(Reference(await f.Workspace()) != first, "Identity expires at the 24-hour boundary; failed reads do not extend it");
        await Error(() => f.Media(first));
        Check(Count(f.Client, "_memberReferences") == 1 && Count(f.Client, "_memberReferenceOrder") == 1,
            "Retention eviction removes both indexes");
    }

    internal static async Task Capacity()
    {
        using var f = new Fixture();
        var first = Reference(await f.Workspace());
        for (var i = 0; i < 500; i++)
        {
            f.Handler.BatchStart = i * 20;
            await f.Workspace();
        }
        Check(Count(f.Client, "_memberReferences") == 10000 && Count(f.Client, "_memberReferenceOrder") == 10000 &&
            Count(f.Client, "_memberTargets") <= 10000, "10,001 unique identities must stay within both memory limits");
        Check(Retained(f.Client, "account:member-one", "A", "scope", false) is null, "The least recently issued identity is evicted first");
        await Error(() => f.Media(first));
        f.Handler.BatchStart = null;
        Check(Reference(await f.Workspace()) != first, "An evicted identity gets a new opaque address on the next validated read");
        f.Client.Dispose();
        Check(Count(f.Client, "_memberReferences") == 0 && Count(f.Client, "_memberReferenceOrder") == 0 &&
            Count(f.Client, "_memberTargets") == 0, "Dispose clears identities and leases together");
    }

    internal static async Task CapacityReusesOldestBatch()
    {
        using var f = new Fixture();
        var now = DateTimeOffset.UtcNow;
        f.Client.MemberReferenceUtcNow = () => now;
        string? oldest = null;
        for (var i = 0; i < 500; i++)
        {
            f.Handler.BatchStart = i * 20;
            var page = await f.Workspace();
            if (i == 0) oldest = Reference(page);
        }
        Check(Count(f.Client, "_memberReferences") == 10000, "Fixture fills the retained mapping");
        now += TimeSpan.FromHours(1);
        Check(Retained(f.Client, "account:batch-1", "A", "scope", false) is not null, "Read-only lookup finds the next oldest member");
        f.Handler.MemberIds = ["account:batch-0", "account:new-b"];
        var result = JsonSerializer.SerializeToElement(await f.Workspace());
        var a = result.GetProperty("members")[0].GetProperty("memberRef").GetString()!;
        var b = result.GetProperty("members")[1].GetProperty("memberRef").GetString()!;
        Check(a == oldest && a != b, "A keeps its identity while B gets its own address");
        await f.Media(a); await f.Media(b);
        Check(Count(f.Client, "_memberReferences") == 10000, "The successful batch stays bounded");
        Check(Retained(f.Client, "account:batch-1", "A", "scope", false) is null, "Read-only lookup must not protect a node from eviction");
        now += TimeSpan.FromHours(23);
        Check(Retained(f.Client, "account:batch-0", "A", "scope", false) == a &&
            Retained(f.Client, "account:new-b", "A", "scope", false) == b, "Renewed A and B survive cleanup of the expired queue prefix");
        now += TimeSpan.FromHours(1);
        Check(Retained(f.Client, "account:batch-0", "A", "scope", false) is null &&
            Retained(f.Client, "account:new-b", "A", "scope", false) is null, "Read-only lookup must not renew retention");
    }

    // Exercise the official author lookup mode separately from lease publication.
    internal static async Task AuthorLookupDoesNotAuthorize()
    {
        using var f = new Fixture();
        var reference = Reference(await f.Workspace());
        ExpireLeases(f.Client);
        Check(Retained(f.Client, "account:member-one", "A", "scope", false) == reference,
            "Official author lookups retain the same opaque identity after authorization expires");
        Check(Retained(f.Client, "account:member-one", "B", "scope", false) is null &&
            Retained(f.Client, "account:member-one", "A", "other", false) is null, "Official author lookup keeps exact scope and code constraints");
        await Error(() => f.Media(reference));
    }

    internal static string? Retained(CommunityClient client, string member, string code, string scope, bool create) =>
        (string?)typeof(CommunityClient).GetMethod("MemberReferenceFor", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(client, [member, code, scope, create, null]);

    private static int Count(CommunityClient client, string field)
    {
        var value = typeof(CommunityClient).GetField(field, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(client)!;
        return (int)value.GetType().GetProperty("Count")!.GetValue(value)!;
    }

    private static JsonElement Query(string targetRef) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef, query = "", offset = 0 });

    private static string Reference(object response) => JsonSerializer.SerializeToElement(response)
        .GetProperty("members")[0].GetProperty("memberRef").GetString()!;

    private static void ExpireLeases(CommunityClient client)
    {
        var entries = (IEnumerable)typeof(CommunityClient).GetField("_memberTargets", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(client)!;
        foreach (var entry in entries)
        {
            var value = entry.GetType().GetProperty("Value")!.GetValue(entry)!;
            value.GetType().GetProperty("Expires")!.SetValue(value, DateTimeOffset.UtcNow.AddMinutes(-1));
        }
    }

    private static async Task Error(Func<Task<object>> read, string code = "communities.refreshRequired")
    {
        try { await read(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException error) when (error.Code == code) { }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }

    private sealed class Fixture : IDisposable
    {
        internal readonly Handler Handler = new();
        internal readonly CommunityClient Client;
        internal readonly string A, B;
        internal Fixture()
        {
            Client = new(new Uri("https://community.invalid"), Handler);
            var page = Client.ReadAsync("fixture", new("mine", "", null, null), "scope", default).GetAwaiter().GetResult();
            A = page.Items[0].TargetRef; B = page.Items[1].TargetRef;
        }
        internal Task<object> Workspace() => Client.ReadWorkspaceAsync("fixture", Query(A), "scope", default);
        internal Task<object> Media(string memberRef, string? targetRef = null, string scope = "scope") => Client.ReadMediaAsync("fixture",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = targetRef ?? A, kind = "avatar", memberRef, offset = 0 }), scope, default);
        internal async Task<string> Source(string source)
        {
            var body = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = A, offset = 0 });
            var value = source switch
            {
                "ships" => await Client.ReadShipsAsync("fixture", body, "scope", () => { }, default),
                "announcements" => await Client.ReadAnnouncementsAsync("fixture", body, "scope", () => { }, default),
                "chat" => await Client.ReadChatAsync("fixture", JsonSerializer.SerializeToElement(new
                    { schemaVersion = 1, targetRef = A, after = 0, before = 0 }), "scope", () => { }, default),
                _ => throw new InvalidOperationException(source)
            };
            var root = JsonSerializer.SerializeToElement(value);
            return source switch
            {
                "ships" => root.GetProperty("ships")[0].GetProperty("ownerMemberRef").GetString()!,
                "announcements" => root.GetProperty("current").GetProperty("author").GetProperty("memberRef").GetString()!,
                _ => root.GetProperty("messages")[0].GetProperty("senderRef").GetString()!
            };
        }
        public void Dispose() => Client.Dispose();
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal int Calls;
        internal bool Invalid;
        internal bool Left;
        internal int? BatchStart;
        internal string[]? MemberIds;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            if (request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath == "/api/fleets/leave")
            {
                Left = true;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { }) });
            }
            var code = request.RequestUri!.Query.Contains("code=B", StringComparison.Ordinal) ? "B" : "A";
            var codes = request.RequestUri.Query.Contains("&code=", StringComparison.Ordinal) ? new[] { code } : new[] { "A", "B" };
            var workspace = CommunityWorkspaceClientTests.Workspace();
            workspace["code"] = code;
            if (MemberIds is not null || BatchStart is not null)
            {
                var member = workspace["members"]![0]!;
                var ids = MemberIds ?? Enumerable.Range(BatchStart!.Value, 20).Select(i => "account:batch-" + i).ToArray();
                workspace["members"] = new JsonArray(ids.Select(id =>
                {
                    var row = member.DeepClone(); row["memberId"] = id; return row;
                }).ToArray());
                workspace["totalCount"] = ids.Length; workspace["matchedCount"] = ids.Length;
            }
            if (Invalid) workspace.AsObject().Remove("access");
            object author = new { accountId = "member-one", callsign = "Fixture", gameId = "", roleTitle = "", roleColor = "#00FF00", avatarImageData = (string?)null };
            object response = request.RequestUri!.AbsolutePath switch
            {
                "/api/fleets/directory" => new
                {
                    schemaVersion = 1, membershipModelVersion = 2, view = request.RequestUri.Query.Contains("view=discover") ? "discover" : "mine", query = "", next = (string?)null,
                    items = codes.Select(itemCode => new { code = itemCode, name = "Fixture", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = Left && itemCode == "A" ? "none" : "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null })
                },
                "/api/fleets/workspace" => workspace,
                "/api/fleets/ships" => new
                {
                    schemaVersion = 1, code = "A", revision = new string('a', 64), totalCount = 1, offset = 0, next = (int?)null,
                    ships = new[] { new { id = new string('a', 64), code = "fixture-ship", displayName = "Fixture", ownerMemberId = "account:member-one",
                        ownerGameName = "", ownerCallsign = "Fixture", ownerOnline = false, ownerLiveStatus = "Offline", ownerIsSelf = false, ownerHasAvatar = true,
                        sharedAt = (string?)null, hangarImportedAt = (string?)null, customImageMediaId = (string?)null,
                        customImageCropFocusX = 0.5, customImageCropFocusY = 0.5, customImageCropZoom = Invalid ? -1.0 : 1.0 } }
                },
                "/api/fleets/announcements" => new
                {
                    schemaVersion = 1, membershipModelVersion = 2, fleetCode = "A", revision = 2L, canManage = false,
                    refreshedAt = "2026-10-30T00:00:00Z", totalHistoryCount = 0, offset = 0, next = (int?)null,
                    current = new { authorHasAvatar = false, lastEditorHasAvatar = false, announcement = new
                    {
                        id = "fixture", fleetCode = "A", title = "Fixture", content = "", revision = 2, state = "Published",
                        publishedAt = "2026-10-30T00:00:00Z", updatedAt = Invalid ? "invalid" : "2026-10-30T00:00:00Z",
                        archivedAt = (string?)null, withdrawnAt = (string?)null, author, lastEditor = author
                    } }, history = Array.Empty<object>()
                },
                "/api/fleets/chat/channels" => new
                {
                    totalUnread = 0, channels = new[] { new { channelId = "fleet:A", type = "fleet", unreadCount = 0, latestSequence = 1, canSend = true } }
                },
                "/api/fleets/chat/messages" => new
                {
                    schemaVersion = 1, channelId = "fleet:A", latestSequence = 1, oldestSequence = Invalid ? 2 : 1, hasOlder = false, canSend = true,
                    serverTime = "2026-10-30T00:00:00Z", messages = new[] { new { sequence = 1, messageId = "fixture", senderAccountId = "member-one",
                        senderCallsign = "Fixture", senderGameId = "", senderRoleTitle = "", senderRoleColor = "#00FF00", text = "fixture",
                        createdAt = "2026-10-30T00:00:00Z", isSelf = false, hasAvatar = true, hasAttachment = false } }
                },
                "/api/fleets/media" => new
                {
                    schemaVersion = 1, kind = "avatar", memberId = Uri.UnescapeDataString(request.RequestUri.Query.Split("&memberId=")[1].Split('&')[0]), version = new string('a', 64),
                    mimeType = "image/png", totalBytes = 1, offset = 0, next = (int?)null, data = "AQ=="
                },
                _ => throw new InvalidOperationException("Unexpected fixture route")
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(response) });
        }
    }
}
