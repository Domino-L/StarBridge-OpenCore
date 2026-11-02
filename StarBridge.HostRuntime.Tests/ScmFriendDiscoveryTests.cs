using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ScmFriendDiscovery()
    {
        using var transport = new DiscoveryTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var friends = new FriendsReader(uri, transport);
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), friends: friends);
        var context = host.CurrentContext!;
        transport.HasFriend = true;
        transport.Mode = "visible";
        var directoryQuery = BridgePayload.From(new { schemaVersion = 1 });
        var directory = await host.ReadFriendsAsync(context, directoryQuery, default);
        Check(directory.Friends.Single().GameId == "allowed-handle" && directory.Friends.Single().Callsign == "Current Callsign",
            "friend list uses Java permitted Handle and current callsign instead of Relay fields");
        transport.Mode = "ok";
        directory = await host.ReadFriendsAsync(context, directoryQuery, default);
        Check(directory.Friends.Single().GameId == "", "hiding clears previously shown Handle on next read");
        transport.Mode = "removed";
        try { await host.ReadFriendsAsync(context, directoryQuery, default); throw new Exception("Expected changed relationship."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "friends.read_unavailable", "relationship removal during identity read invalidates directory"); }
        transport.Mode = "ok";
        transport.HasFriend = false;
        var query = BridgePayload.From(new { schemaVersion = 1, query = "Aurora" });
        var found = await host.ReadFriendsAsync(context, query, default);
        Check(found.Results.Length == 1 && found.Results[0].GameId == "" && found.Results[0].Actions.Contains("send"), "SCM discovery yields private Handle and opaque command target");
        Check(!JsonSerializer.Serialize(found).Contains(DiscoveryTransport.Id), "business ID never crosses UI bridge");
        var command = BridgePayload.From(new { schemaVersion = 1, action = "send", targetRef = found.Results[0].TargetRef });
        var outcome = await host.ExecuteFriendAsync(context, command, default);
        Check(outcome.Status == "accepted" && transport.Searches == 2 && transport.Writes == 1,
            "SCM search revalidated before existing Relay friend action, never legacy search");
        Check((await host.ExecuteFriendAsync(context, command, default)).Status == "rejected" && transport.Writes == 1, "consumed target cannot replay write");
        transport.Mode = "down";
        try { await host.ReadFriendsAsync(context, query, default); throw new Exception("Expected search unavailable."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "friends.read_transient" && error.Retryable, "Java outage stays retryable without fallback"); }
        transport.Mode = "extra";
        try { await host.ReadFriendsAsync(context, query, default); throw new Exception("Expected invalid projection."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "friends.data_invalid", "extra authority field rejected"); }
        transport.Mode = "large";
        try { await host.ReadFriendsAsync(context, query, default); throw new Exception("Expected oversized projection."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "friends.data_invalid", "oversized response rejected"); }
        transport.Mode = "ok";
        transport.HasFriend = true;
        transport.Mode = "legacy-directory";
        int identitiesBefore = transport.IdentityReads;
        directory = await host.ReadFriendsAsync(context, directoryQuery, default);
        Check(directory.Friends.Length == 3 && directory.Friends.All(row => row.Callsign == "测试呼号"),
            "SCM compatibility login retains all three authorized legacy friends without requiring SCM identities");
        Check(directory.Friends.All(row => row.GameId == "Citizen_CN"),
            "legacy friend display uses the authorized Relay privacy projection");
        Check(transport.Writes == 1, "compatibility directory reads never migrate or create friends");
        Check(transport.IdentityReads == identitiesBefore, "legacy friends never require Java identity lookup");
        transport.Mode = "legacy-hidden";
        directory = await host.ReadFriendsAsync(context, directoryQuery, default);
        Check(directory.Friends.All(row => row.GameId == ""), "Relay-hidden legacy Handles remain hidden");
        transport.Mode = "mixed-directory";
        directory = await host.ReadFriendsAsync(context, directoryQuery, default);
        Check(directory.Friends.Length == 4 && directory.Friends.Count(row => row.Callsign == "Current Callsign") == 1,
            "mixed directory preserves legacy friends and projects SCM identity separately");
        Check(directory.Friends.Single(row => row.Callsign == "Current Callsign").GameId == "",
            "mixed directory never exposes the Relay copy of a SCM Handle");
        transport.Mode = "malformed-scm-directory";
        try { await host.ReadFriendsAsync(context, directoryQuery, default); throw new Exception("Expected malformed SCM rejection."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "friends.data_invalid", "malformed SCM IDs cannot bypass Java identity privacy"); }
        transport.Mode = "mixed-down";
        try { await host.ReadFriendsAsync(context, directoryQuery, default); throw new Exception("Expected identity outage."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "friends.read_transient" && error.Retryable, "Java outage never falls back to Relay SCM identity fields"); }
        transport.Mode = "ok";
        transport.HasFriend = false;
        await LinkedSearch(host, context, transport);
        await host.LogoutAsync(context, default);
        int before = transport.Searches;
        try { await host.ReadFriendsAsync(context, query, default); throw new Exception("Expected stale identity."); }
        catch (AccountBridgeHostException) { }
        Check(transport.Searches == before, "logged out owner cannot issue discovery");
    }

    /// <summary>A linked viewer's friends are listed under a legacy identity search never returns.</summary>
    private static async Task LinkedSearch(ScmAccountBridgeHost host, BridgeAccountContext context, DiscoveryTransport transport)
    {
        var writes = transport.Writes;
        var searches = transport.Searches;
        var query = BridgePayload.From(new { schemaVersion = 1, query = "Aurora" });
        transport.Linked = true;
        transport.LegacyFriendName = "Aurora";
        transport.LegacyFriendHandle = "Aurora-CN";
        transport.Relationships = new { schemaVersion = 1, rows = new[] { new { id = DiscoveryTransport.Id, relationship = "friend", addable = true, blockable = true } } };
        var merged = await host.ReadFriendsAsync(context, query, default);
        Check(merged.Friends.Single().Callsign == "Aurora" && merged.Results.Length == 0,
            "a confirmed friend with the same name is one row, under the friend list identity");
        Check(merged.Friends.Single().ChatTargetRef is not null, "the listed friend opens chat as in the list");
        var serialized = JsonSerializer.Serialize(merged);
        Check(!serialized.Contains("legacy-friend-") && !serialized.Contains(DiscoveryTransport.Id), "no internal identity crosses the bridge");

        transport.LegacyFriendName = "Someone Else";
        transport.LegacyFriendHandle = "";
        var unmerged = await host.ReadFriendsAsync(context, query, default);
        Check(unmerged.Friends.Length == 0 && unmerged.Results.Single().Relationship == "friend" &&
              !unmerged.Results.Single().Actions.Contains("send") && unmerged.Results.Single().ChatTargetRef is null,
            "a friend who cannot be matched by name is never offered a request, and chat is not guessed");

        // The list last shown does not contain this friend yet.
        transport.LegacyFriendName = null;
        await host.ReadFriendsAsync(context, BridgePayload.From(new { schemaVersion = 1 }), default);
        transport.LegacyFriendName = "Someone Else";
        transport.Linked = false;
        transport.HasFriend = true;
        transport.Mode = "ok";
        transport.Relationships = null;
        var notListedYet = await host.ReadFriendsAsync(context, query, default);
        Check(notListedYet.Results.Single().Callsign == "Aurora" && notListedYet.Results.Single().Relationship == "friend",
            "a friend the list has not shown stays in the results rather than vanishing");
        transport.HasFriend = false;
        transport.Linked = true;
        transport.Relationships = new { schemaVersion = 1, rows = new[] { new { id = DiscoveryTransport.Id, relationship = "none", addable = false, blockable = false } } };
        transport.LegacyFriendHandle = "aurora-hidden";
        transport.Relationships = new { schemaVersion = 1, rows = new[] { new { id = DiscoveryTransport.Id, relationship = "none", addable = false, blockable = false } } };
        var notAddable = await host.ReadFriendsAsync(context, query, default);
        Check(notAddable.Friends.Single().GameId == "aurora-hidden", "a friend also matches on the listed Handle");
        Check(notAddable.Results.Single().Actions.Length == 0 && notAddable.Results.Single().TargetRef is not null,
            "a person Relay cannot reach stays readable without commands");
        var refused = await host.ExecuteFriendAsync(context, BridgePayload.From(new { schemaVersion = 1, action = "send",
            targetRef = notAddable.Results.Single().TargetRef }), default);
        Check(refused.Status == "rejected" && transport.Writes == writes, "an unreachable person cannot be written to");

        transport.LegacyFriendHandle = "";
        transport.Relationships = new { schemaVersion = 1, rows = new[] { new { id = DiscoveryTransport.Id, relationship = "none", addable = true, blockable = false } } };
        var addable = await host.ReadFriendsAsync(context, query, default);
        Check(addable.Friends.Length == 0 && addable.Results.Single().Actions.Contains("send"), "a reachable person can be added");
        Check(!addable.Results.Single().Actions.Contains("block"), "a block Relay would refuse is not offered");
        var refusedBlock = await host.ExecuteFriendAsync(context, BridgePayload.From(new { schemaVersion = 1, action = "block",
            targetRef = addable.Results.Single().TargetRef }), default);
        Check(refusedBlock.Status == "rejected" && transport.Writes == writes, "a refused block is never sent");
        addable = await host.ReadFriendsAsync(context, query, default);
        transport.LastWriteSeen = false;
        transport.RelationshipsAfterWrite = new { schemaVersion = 1, rows = new[] { new { id = DiscoveryTransport.Id, relationship = "outgoing", addable = true, blockable = true } } };
        var sent = await host.ExecuteFriendAsync(context, BridgePayload.From(new { schemaVersion = 1, action = "send",
            targetRef = addable.Results.Single().TargetRef }), default);
        Check(sent.Status == "accepted" && sent.Directory is not null && transport.Writes == writes + 1,
            "a request listed under another identity is confirmed by asking about the searched one");
        transport.RelationshipsAfterWrite = null;

        foreach (var broken in new object?[] { null,
            new { schemaVersion = 2, rows = Array.Empty<object>() },
            new { schemaVersion = 1, rows = new[] { new { id = "scm-v1:other", relationship = "none", addable = false, blockable = false } } },
            new { schemaVersion = 1, rows = new[] { new { id = DiscoveryTransport.Id, relationship = "self", addable = false, blockable = false } } },
            new { schemaVersion = 1, rows = new[] { new { id = DiscoveryTransport.Id, relationship = "none", addable = false } } } })
        {
            transport.Relationships = broken;
            var plain = await host.ReadFriendsAsync(context, query, default);
            Check(plain.Results.Single().Relationship == "none" && plain.Results.Single().Actions.Contains("send"),
                "an old relay or an unusable answer keeps the plain search result");
        }
        transport.Relationships = null;
        transport.LegacyFriendName = null;
        transport.Linked = false;
        Check(transport.Searches > searches, "search still reaches Java");
    }

    private sealed class DiscoveryTransport : HttpMessageHandler
    {
        internal bool Linked;
        internal string? LegacyFriendName, LegacyFriendHandle;
        internal object? Relationships, RelationshipsAfterWrite;
        internal static readonly string Id = "scm-v1:" + new string('a', 64);
        internal int Searches, Writes, IdentityReads;
        internal bool HasFriend;
        internal string Mode = "ok";
        internal bool LastWriteSeen;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "read-token", "only active SCM bearer");
            var path = request.RequestUri!.AbsolutePath;
            if (path.EndsWith("/friend-identity", StringComparison.Ordinal)) {
                IdentityReads++;
                Check(request.Method == HttpMethod.Get && request.RequestUri.Query == "", "friend identity uses scoped GET");
                if (Mode == "mixed-down") return new(HttpStatusCode.ServiceUnavailable);
                if (Mode == "removed") HasFriend = false;
                return Reply(new { schemaVersion = 1, businessSubjectId = Id, callSign = "Current Callsign", handle = Mode == "visible" ? "allowed-handle" : "" });
            }
            if (path == "/app-api/starbridge/v1/participants/search") {
                Searches++;
                Check(request.Method == HttpMethod.Post && request.RequestUri.Query == "", "search term stays out of URL");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.EnumerateObject().Count() == 1 && body.RootElement.GetProperty("query").GetString() == "Aurora", "no caller target identity");
                if (Mode == "down") return new(HttpStatusCode.ServiceUnavailable);
                if (Mode == "large") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 65537)) };
                if (Mode == "extra") return Reply(new { schemaVersion = 1, users = new[] { new { businessSubjectId = Id, callSign = "Aurora", handle = "", subject = "private" } } });
                return Reply(new { schemaVersion = 1, users = new[] { new { businessSubjectId = Id, callSign = "Aurora", handle = "" } } });
            }
            if (path == "/api/friends/relationships") {
                Check(request.Method == HttpMethod.Post && request.RequestUri.Query == "", "ids stay out of the URL");
                var answer = Writes > 0 && RelationshipsAfterWrite is not null && LastWriteSeen ? RelationshipsAfterWrite : Relationships;
                return answer is null ? new(HttpStatusCode.NotFound) : Reply(answer);
            }
            Check(path is "/api/friends" or "/api/friends/actions", "SCM never calls legacy friend-search endpoint");
            if (path == "/api/friends/actions") {
                Writes++;
                Check(Searches >= 2 && request.Method == HttpMethod.Post, "write follows fresh discovery");
                LastWriteSeen = true;
            }
            if (Linked) {
                // The linked graph: search subjects never appear in this list.
                object[] listed = LegacyFriendName is null ? [] : [new { user = new { accountId = "legacy-friend-linked", callsign = LegacyFriendName,
                    gameId = LegacyFriendHandle ?? "", relationshipState = "friend", lastUpdated = FriendsReaderTests.Now }, relationshipUpdatedAt = FriendsReaderTests.Now }];
                return Reply(new { friends = listed, incomingRequests = Array.Empty<object>(), outgoingRequests = Array.Empty<object>(),
                    blockedUsers = Array.Empty<object>(), refreshedAt = FriendsReaderTests.Now });
            }
            object[] outgoing = Writes == 0 || HasFriend && Mode == "ok" || Mode is "mixed-directory" or "mixed-down" ? [] : [new { user = FriendsReaderTests.User(Id, "outgoing"), relationshipUpdatedAt = FriendsReaderTests.Now }];
            object[] confirmed = Mode is "legacy-directory" or "legacy-hidden" or "mixed-directory" or "mixed-down"
                ? Enumerable.Range(1, 3).Select(index => (object)new {
                    user = new { accountId = "legacy-friend-" + index, callsign = "测试呼号",
                        gameId = Mode == "legacy-hidden" ? "" : "Citizen_CN", relationshipState = "friend",
                        lastUpdated = FriendsReaderTests.Now }, relationshipUpdatedAt = FriendsReaderTests.Now
                }).ToArray()
                : HasFriend ? [new { user = FriendsReaderTests.User(Id, "friend"), relationshipUpdatedAt = FriendsReaderTests.Now }] : [];
            if (Mode is "mixed-directory" or "mixed-down") confirmed = [.. confirmed,
                new { user = FriendsReaderTests.User(Id, "friend"), relationshipUpdatedAt = FriendsReaderTests.Now }];
            if (Mode == "malformed-scm-directory") confirmed = [
                new { user = FriendsReaderTests.User("scm-v1:invalid", "friend"), relationshipUpdatedAt = FriendsReaderTests.Now }];
            return Reply(new { friends = confirmed, incomingRequests = Array.Empty<object>(), outgoingRequests = outgoing,
                blockedUsers = Array.Empty<object>(), refreshedAt = FriendsReaderTests.Now });
        }
        private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
}
