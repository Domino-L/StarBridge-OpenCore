using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record AvatarTarget(string Source, string Reference, string? Context, string Query);
    private static AvatarTarget ParseAvatarTarget(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Distinct().Count() != names.Length || names.Any(n => n is not
                ("schemaVersion" or "source" or "reference" or "contextRef" or "query")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1) throw new FormatException();
            var source = payload.GetProperty("source").GetString()!;
            var reference = payload.GetProperty("reference").GetString()!;
            var context = payload.TryGetProperty("contextRef", out var c) ? c.GetString() : null;
            var query = payload.TryGetProperty("query", out var q) ? q.GetString() ?? "" : "";
            if (source is not ("community" or "communityApplicant" or "friend" or "conversation" or "room") ||
                !Guid.TryParseExact(reference, "N", out _) || query.Length > 128 || query.Any(char.IsControl) ||
                (source is "community" or "communityApplicant" ? !Guid.TryParseExact(context, "N", out _) : context != null)) throw new FormatException();
            return new(source, reference, context, query);
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException)
        { throw new AccountBridgeHostException("users.invalid_request"); }
    }

    private async Task<string> ResolveAvatarAsync(AvatarTarget target, RelayRequestSession session, string scope,
        BridgeAccountContext context, long generation, CancellationToken token)
    {
        if (target.Source == "communityApplicant")
        {
            if (session.Legacy is null || _communities is null) throw new AccountBridgeHostException("profile.visitor_unavailable");
            void Current()
            {
                if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
                RequireSameRelaySession(session, RequireRelaySession(context));
            }
            var result = await SendRelayRequestAsync(session, (active, ct) =>
                _communities.ResolveApplicantIdentityAsync(active.AccessToken, target.Context!, target.Reference,
                    scope, session.Legacy.AccountId, Current, ct), token);
            Current();
            return result.Result;
        }
        if (target.Source == "community")
        {
            if (session.Legacy is null || _communities is null) throw new AccountBridgeHostException("profile.visitor_unavailable");
            return _communities.ResolveVisitorProfileTarget(JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, targetRef = target.Context, memberRef = target.Reference
            }), scope, session.Legacy.AccountId);
        }
        if (target.Source == "room") return ResolveRoomAvatar(target.Reference, scope);
        return (_friends ?? throw new AccountBridgeHostException("friends.read_unavailable"))
            .ResolveAvatarTarget(target.Source, target.Reference, session.AccessToken, scope);
    }

    public async Task<PersonalProfileDocumentContract> ReadUserProfileAsync(BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        var target = ParseAvatarTarget(payload);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable || session.Legacy is null || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("profile.visitor_unavailable");
        var id = await ResolveAvatarAsync(target, session, FriendScope(context, generation), context, generation, token);
        var result = await SendRelayRequestAsync(session,
            (active, ct) => _legacyPasswordLogin.ReadVisitorProfileAsync(active.Legacy!, id, ct), token);
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(session, RequireRelaySession(context));
        return result.Result;
    }

    public async Task<FriendsView> ReadUserSocialAsync(BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        var target = ParseAvatarTarget(payload);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var scope = FriendScope(context, generation);
        var id = await ResolveAvatarAsync(target, session, scope, context, generation, token);
        if (id == session.Legacy?.AccountId)
            return new(null, DateTimeOffset.UtcNow, [], [], [], [], [new("", "", "self", null, DateTimeOffset.UtcNow)]);
        void Current() {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(session, RequireRelaySession(context));
        }
        var result = await SendRelayRequestAsync(session, (active, ct) =>
            (_friends ?? throw new AccountBridgeHostException("friends.read_unavailable"))
                .ReadAvatarSocialAsync(active.AccessToken, id, target.Query, scope, Current, ct), token);
        Current();
        return result.Result;
    }
}
