using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Friends;

internal sealed partial class FriendsReader
{
    private readonly Dictionary<string, Target> _avatarTargets = new(StringComparer.Ordinal);
    private void RememberAvatar(string reference, Target target)
    {
        foreach (var key in _avatarTargets.Where(p => p.Value.Expires <= DateTimeOffset.UtcNow || p.Value.Owner != target.Owner)
                     .Select(p => p.Key).ToArray()) _avatarTargets.Remove(key);
        if (_avatarTargets.Count >= 4096) _avatarTargets.Clear();
        _avatarTargets[reference] = target;
    }
    internal string ResolveAvatarTarget(string source, string reference, string bearer, string scope)
    {
        lock (_targetGate)
        {
            var owner = Owner(bearer, scope);
            if (source == "friend" && _avatarTargets.TryGetValue(reference, out var friend) &&
                friend.Owner == owner && friend.Expires > DateTimeOffset.UtcNow) return friend.Id;
            if (source == "conversation" && _conversations.TryGetValue(reference, out var chat) &&
                chat.Owner == owner && chat.Expires > DateTimeOffset.UtcNow) {
                RememberAvatar(reference, new(owner, chat.Id, "conversation", null, chat.Expires));
                return chat.Id;
            }
            if (source == "conversation" && _avatarTargets.TryGetValue(reference, out var previous) &&
                previous.Relation == "conversation" && previous.Owner == owner && previous.Expires > DateTimeOffset.UtcNow) return previous.Id;
        }
        throw new AccountBridgeHostException("users.targetChanged");
    }

    internal async Task<FriendsView> ReadAvatarSocialAsync(string bearer, string id, string query,
        string scope, Action current, CancellationToken token)
    {
        // Search is a discovery hint only. An exact authoritative account ID
        // match is mandatory; never substitute a same-name search result.
        var directory = await ReadAsync(bearer, null, token, scope, issueTargets: false);
        current();
        var row = All(directory).SingleOrDefault(item => item.AccountId == id);
        string? effectiveQuery = null;
        if (row is null && query.Length >= 2)
        {
            directory = await ReadAsync(bearer, query, token, scope, issueTargets: false);
            current();
            effectiveQuery = query;
            row = All(directory).SingleOrDefault(item => item.AccountId == id);
        }
        if (row is null) return new(null, DateTimeOffset.UtcNow, [], [], [], [], []);
        current();
        row = IssueTargets(new(effectiveQuery, directory.RefreshedAt, [], [], [], [], [row]),
            bearer, scope, append: true).Results.Single();
        if (row.ChatTargetRef is null && row.Relationship is "none" or "incoming" or "outgoing")
        {
            lock (_targetGate)
            {
                current();
                var owner = Owner(bearer, scope);
                var reference = Guid.NewGuid().ToString("N");
                _conversations[reference] = new(owner, id, DateTimeOffset.UtcNow.AddMinutes(30), DisplayName: row.Callsign);
                _friendChatTargets.Add(reference);
                row = row with { ChatTargetRef = reference, ConversationKey = ConversationKey(owner, id, scope) };
            }
        }
        // Reuse the established command preflight and no-replay write path.
        // Chat read/send still enforces the server's recipient privacy policy.
        return new(effectiveQuery, directory.RefreshedAt, [], [], [], [], [row]);
    }
}
