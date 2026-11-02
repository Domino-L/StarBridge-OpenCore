using System.Text.Json;

namespace StarBridge.HostRuntime.Friends;

internal sealed partial class FriendsReader
{
    internal static bool IsScmBusinessId(string? id) => id is { Length: 71 } && id.StartsWith("scm-v1:", StringComparison.Ordinal)
        && id.Skip(7).All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');

    internal static FriendView ParseScmFriendIdentity(byte[] bytes, string expectedId)
    {
        try {
            if (bytes.Length > 64 * 1024) throw Invalid();
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            RejectDuplicates(root);
            if (root.EnumerateObject().Count() != 4 || root.GetProperty("schemaVersion").GetInt32() != 1 ||
                Text(root, "businessSubjectId", 71) != expectedId || !IsScmBusinessId(expectedId)) throw Invalid();
            var name = Text(root, "callSign", 128);
            if (string.IsNullOrWhiteSpace(name)) throw Invalid();
            return new(name, Text(root, "handle", 128), "friend", null, DateTimeOffset.UtcNow) { AccountId = expectedId };
        } catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) {
            throw Invalid();
        }
    }
    internal static FriendsView ParseScmSearch(byte[] bytes, string query)
    {
        try {
            if (bytes.Length > 64 * 1024) throw Invalid();
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            RejectDuplicates(root);
            if (root.EnumerateObject().Count() != 2 || root.GetProperty("schemaVersion").GetInt32() != 1) throw Invalid();
            var users = root.GetProperty("users");
            if (users.GetArrayLength() > 20) throw Invalid();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            var rows = users.EnumerateArray().Select(user => {
                if (user.EnumerateObject().Count() != 3) throw Invalid();
                var id = Text(user, "businessSubjectId", 71);
                var name = Text(user, "callSign", 128);
                var handle = Text(user, "handle", 128);
                if (!IsScmBusinessId(id) || !seen.Add(id) || string.IsNullOrWhiteSpace(name)) throw Invalid();
                return new FriendView(name, handle, "none", null, DateTimeOffset.UtcNow) { AccountId = id };
            }).ToArray();
            return new(query, null, [], [], [], [], rows);
        } catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) {
            throw Invalid();
        }
    }

    internal async Task<FriendsView> ReadScmSearchAsync(string bearer, string query,
        Func<string, CancellationToken, Task<FriendsView>> search, CancellationToken token, string scope, Action ensureCurrent)
    {
        var found = await search(query, token);
        // Relay owns relationships, Java owns searchable identity/Handle. Do not merge Relay identity fields.
        var directory = await ReadAsync(bearer, null, token, scope, issueTargets: false);
        var relations = All(directory).ToDictionary(row => row.AccountId, row => row.Relationship, StringComparer.Ordinal);
        // Linked accounts are listed under a legacy identity that search never returns.
        var current = await ReadScmRelationshipsAsync(bearer, found.Results.Select(row => row.AccountId).ToArray(), token);
        var results = found.Results.Select(row => {
            if (relations.TryGetValue(row.AccountId, out var relation)) return row with { Relationship = relation };
            if (current is null || !current.TryGetValue(row.AccountId, out var state)) return row;
            return row with { Relationship = state.Relationship, Addable = state.Addable, Blockable = state.Blockable,
                ChatAvailable = state.Relationship != "friend" };
        }).Where(row => row.Relationship != "blocked").ToArray();
        var friends = MatchListedFriends(directory, results, query, Owner(bearer, scope));
        var projected = found with { Friends = friends, Results = results
            .Where(row => friends.All(friend => friend.AccountId != row.AccountId))
            // Only against a friend who is shown: otherwise the person would be in neither group.
            .Where(row => row.Relationship != "friend" || !friends.Any(friend => SamePerson(friend, row))).ToArray() };
        token.ThrowIfCancellationRequested();
        ensureCurrent();
        return IssueTargets(projected, bearer, scope);
    }

    private sealed record ListedFriends(string Owner, DateTimeOffset ReadAt, FriendView[] Rows);
    private ListedFriends? _listedFriends;
    // The list is refreshed while open, so what it last showed goes stale quickly once a search replaces it.
    private static readonly TimeSpan ListedSharedAge = TimeSpan.FromMinutes(2);

    /// <summary>
    /// Friends this search also applies to, from what the list already shows: no extra request, and a Handle the
    /// friend keeps hidden is blank here too. A friend the search itself returned counts whatever matched them.
    /// </summary>
    private FriendView[] MatchListedFriends(FriendsView directory, FriendView[] results, string query, string owner)
    {
        ListedFriends? listed;
        lock (_targetGate) listed = _listedFriends;
        var shown = listed is not null && listed.Owner == owner
            ? listed.Rows.ToDictionary(row => row.AccountId, StringComparer.Ordinal)
            : new Dictionary<string, FriendView>(StringComparer.Ordinal);
        var currentShared = listed is not null && DateTimeOffset.UtcNow - listed.ReadAt < ListedSharedAge;
        var found = results.Select(row => row.AccountId).ToHashSet(StringComparer.Ordinal);
        return directory.Friends.Select(row => shown.TryGetValue(row.AccountId, out var known)
                ? row with { Callsign = known.Callsign, GameId = known.GameId, Shared = currentShared ? known.Shared : null }
                // The Relay copy of an SCM identity is never displayed.
                : IsScmBusinessId(row.AccountId) ? null : row)
            .OfType<FriendView>()
            .Where(row => found.Contains(row.AccountId) || Contains(row.Callsign, query) || Contains(row.GameId, query))
            .ToArray();
    }

    private static bool Contains(string value, string query) => value.Contains(query, StringComparison.OrdinalIgnoreCase);
    private static bool SamePerson(FriendView friend, FriendView result)
    {
        static bool Same(string left, string right) => left.Length != 0 && left.Equals(right, StringComparison.OrdinalIgnoreCase);
        return Same(friend.GameId, result.GameId) || Same(friend.Callsign, result.Callsign) ||
            Same(friend.GameId, result.Callsign) || Same(friend.Callsign, result.GameId);
    }

    /// <summary>
    /// Relay's answer for these search results, or null when it has none: relays before this route answer 404, and
    /// any failure keeps the plain search result, where Relay still rejects what it cannot deliver.
    /// </summary>
    internal async Task<IReadOnlyDictionary<string, ScmRelationship>?> ReadScmRelationshipsAsync(
        string bearer, string[] ids, CancellationToken token)
    {
        if (ids.Length == 0) return null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(5));
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/friends/relationships"));
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", bearer);
        request.Content = System.Net.Http.Json.JsonContent.Create(new { schemaVersion = 1, ids });
        try {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            return response.IsSuccessStatusCode ? ParseScmRelationships(await CommandBody(response, deadline.Token), ids) : null;
        } catch (Exception error) when (!token.IsCancellationRequested && error is HttpRequestException or IOException or
            OperationCanceledException or JsonException or InvalidOperationException or Account.AccountBridgeHostException) {
            return null;
        }
    }

    internal sealed record ScmRelationship(string Relationship, bool Addable, bool Blockable);

    internal static IReadOnlyDictionary<string, ScmRelationship>? ParseScmRelationships(byte[] bytes, string[] ids)
    {
        try {
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            RejectDuplicates(root);
            if (root.EnumerateObject().Count() != 2 || root.GetProperty("schemaVersion").GetInt32() != 1) return null;
            var rows = new Dictionary<string, ScmRelationship>(StringComparer.Ordinal);
            foreach (var row in root.GetProperty("rows").EnumerateArray()) {
                var relationship = row.GetProperty("relationship").GetString();
                if (row.EnumerateObject().Count() != 4 || row.GetProperty("id").GetString() is not { } id || !ids.Contains(id, StringComparer.Ordinal) ||
                    relationship is not ("none" or "friend" or "incoming" or "outgoing" or "blocked") ||
                    !rows.TryAdd(id, new(relationship, row.GetProperty("addable").GetBoolean(), row.GetProperty("blockable").GetBoolean()))) return null;
            }
            return rows.Count == ids.Length ? rows : null;
        } catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or Account.AccountBridgeHostException) {
            return null;
        }
    }

    internal async Task<FriendsView> ReadScmDirectoryAsync(string bearer,
        Func<string, CancellationToken, Task<FriendView>> identity, CancellationToken token, string scope, bool observe, Action ensureCurrent)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        var probePhase = FriendsProbePhase.DirectoryInitial;
        try {
            var initial = await ReadAsync(bearer, null, deadline.Token, scope, observe, sharing: true, issueTargets: false);
            var projected = new System.Collections.Concurrent.ConcurrentDictionary<string, FriendView>(StringComparer.Ordinal);
            probePhase = FriendsProbePhase.ScmIdentity;
            await Parallel.ForEachAsync(initial.Friends, new ParallelOptions { MaxDegreeOfParallelism = 4, CancellationToken = deadline.Token },
                async (row, cancellation) => {
                    // The authenticated Relay directory also contains legacy friends for linked accounts.
                    // Their identity and privacy projection belongs to Relay, not Java participant discovery.
                    // Never reinterpret a malformed SCM identity as a legacy identity.
                    if (!IsScmBusinessId(row.AccountId))
                    {
                        if (row.AccountId.StartsWith("scm-", StringComparison.OrdinalIgnoreCase)) throw Invalid();
                        return;
                    }
                    var current = await identity(row.AccountId, cancellation);
                    if (current.AccountId != row.AccountId) throw Invalid();
                    projected[row.AccountId] = current;
                });
            // A newly blocked or removed friend must not be restored from the pre-await list.
            probePhase = FriendsProbePhase.RelationshipRecheck;
            var latest = initial.Friends.Length == 0 ? initial :
                await ReadAsync(bearer, null, deadline.Token, scope, observe, sharing: true, issueTargets: false);
            probePhase = FriendsProbePhase.DirectoryProjection;
            var before = initial.Friends.Select(row => row.AccountId).Order(StringComparer.Ordinal);
            var after = latest.Friends.Select(row => row.AccountId).Order(StringComparer.Ordinal);
            if (!before.SequenceEqual(after, StringComparer.Ordinal)) throw new Account.AccountBridgeHostException("friends.read_unavailable", true);
            FriendView[] Hidden(FriendView[] rows) => rows.Select(row => row with { GameId = "" }).ToArray();
            latest = latest with {
                Friends = latest.Friends.Select(row => projected.TryGetValue(row.AccountId, out var scmIdentity)
                    ? row with { Callsign = scmIdentity.Callsign, GameId = scmIdentity.GameId }
                    : row).ToArray(),
                Incoming = Hidden(latest.Incoming), Outgoing = Hidden(latest.Outgoing), Blocked = Hidden(latest.Blocked), Results = []
            };
            token.ThrowIfCancellationRequested(); ensureCurrent();
            FriendsReadProbeDiagnostics.Record(probePhase);
            lock (_targetGate) _listedFriends = new(Owner(bearer, scope), DateTimeOffset.UtcNow, latest.Friends);
            return IssueTargets(latest, bearer, scope);
        } catch (Exception error) when (probePhase == FriendsProbePhase.RelationshipRecheck && !token.IsCancellationRequested &&
            (error is not Account.AccountBridgeHostException ||
                error is Account.AccountBridgeHostException { Code: "friends.read_transient", Retryable: true })) {
            // The pre-await directory may now contain a removed or blocked friend.
            // A retry is safe, but retaining that unconfirmed cached display is not.
            // Preserve classified rejections; they already prohibit cache retention.
            var failure = new Account.AccountBridgeHostException("friends.read_unavailable", true);
            FriendsReadProbeDiagnostics.Record(probePhase, 0, failure);
            throw failure;
        } catch (OperationCanceledException error) when (!token.IsCancellationRequested) {
            FriendsReadProbeDiagnostics.Record(probePhase, 0, error);
            throw FriendsReadFailures.FromTransport(error, token);
        } catch (Exception error) {
            FriendsReadProbeDiagnostics.Record(probePhase, 0, error);
            throw;
        }
    }
}
