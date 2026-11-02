using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly PublicOrganizationLogoReader _publicOrganizationLogos;

    // A non-null affiliation on an authorized visitor document is the server's
    // visibility projection. Never recover hidden affiliations from other sources.
    // The SCM document leaves Kind empty for the main fleet; only communities
    // are marked, matching how the client reads it. The logo is decoration:
    // wait briefly, then show the page without it (the cache fills for next time).
    private async Task<PersonalProfileDocumentContract> WithVisitorLogoAsync(
        PersonalProfileDocumentContract profile, CancellationToken token)
    {
        if (profile.FleetAffiliation is not { } affiliation ||
            affiliation.Kind is not (null or "officialFleet") ||
            !string.IsNullOrWhiteSpace(affiliation.LogoImageData)) return profile;
        var pending = _publicOrganizationLogos.ReadAsync(affiliation.FleetCode);
        var finished = await Task.WhenAny(pending, Task.Delay(VisitorLogoWait, token)).ConfigureAwait(false);
        var logo = finished == pending ? await pending.ConfigureAwait(false) : null;
        return logo is null ? profile : profile with { FleetAffiliation = affiliation with { LogoUrl = logo.Image } };
    }

    private static readonly TimeSpan VisitorLogoWait = TimeSpan.FromSeconds(2);

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
            var officialFleet = source == "officialFleet";
            if (source is not ("community" or "communityApplicant" or "friend" or "conversation" or "room" or "officialFleet" or "market") ||
                (officialFleet ? reference is not { Length: 64 } || reference.AsSpan().IndexOfAnyExcept("0123456789abcdef") >= 0
                    : !Guid.TryParseExact(reference, "N", out _)) || query.Length > 128 || query.Any(char.IsControl) ||
                (officialFleet ? context is null || !System.Text.RegularExpressions.Regex.IsMatch(context, "^officialFleet:[1-9][0-9]{0,18}$")
                    : source is "community" or "communityApplicant" ? !Guid.TryParseExact(context, "N", out _) : context != null)) throw new FormatException();
            return new(source, reference, context, query);
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException)
        { throw new AccountBridgeHostException("users.invalid_request"); }
    }

    private async Task<string> ResolveAvatarAsync(AvatarTarget target, RelayRequestSession session, string scope,
        BridgeAccountContext context, long generation, CancellationToken token, bool profileRead = false)
    {
        if (target.Source == "market")
        {
            if (!profileRead) throw new AccountBridgeHostException("users.invalid_request");
            if (session.Scm is null) throw new AccountBridgeHostException("profile.visitor_unavailable");
            return ResolveMarketTrader(target.Reference, scope);
        }
        if (target.Source == "officialFleet")
            return await ResolveOfficialFleetProfileTargetAsync(target, context, generation, token);
        if (target.Source == "communityApplicant")
        {
            if (_communities is null) throw new AccountBridgeHostException("profile.visitor_unavailable");
            void Current()
            {
                if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
                RequireSameRelaySession(session, RequireRelaySession(context));
            }
            var result = await SendRelayRequestAsync(session, (active, ct) =>
                _communities.ResolveApplicantIdentityAsync(active.AccessToken, target.Context!, target.Reference,
                    scope, session.Legacy?.AccountId, Current, ct), token);
            Current();
            return result.Result;
        }
        if (target.Source == "community")
        {
            if (_communities is null) throw new AccountBridgeHostException("profile.visitor_unavailable");
            return _communities.ResolveVisitorProfileTarget(JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, targetRef = target.Context, memberRef = target.Reference
            }), scope, session.Legacy?.AccountId, allowHistoricalProfile: profileRead && session.Scm is not null);
        }
        if (target.Source == "room") return await ResolveRoomAvatarAsync(target.Reference, scope, session, context, generation, token);
        return (_friends ?? throw new AccountBridgeHostException("friends.read_unavailable"))
            .ResolveAvatarTarget(target.Source, target.Reference, session.AccessToken, scope);
    }

    public async Task<PersonalProfileDocumentContract> ReadUserProfileAsync(BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        using var observation = StarBridge.HostRuntime.Auth.VisitorReadDiagnostics.Begin();
        try
        {
            var profile = await ReadUserProfileCoreAsync(context, payload, token);
            StarBridge.HostRuntime.Auth.VisitorReadDiagnostics.Write(StarBridge.HostRuntime.Auth.VisitorReadDiagnostics.Phase.Completed);
            return profile;
        }
        catch (PersonalProfileRestrictedException)
        {
            // A visibility-restricted page is a completed read with only the public header.
            StarBridge.HostRuntime.Auth.VisitorReadDiagnostics.Write(StarBridge.HostRuntime.Auth.VisitorReadDiagnostics.Phase.Completed);
            throw;
        }
        catch (Exception failure)
        {
            StarBridge.HostRuntime.Auth.VisitorReadDiagnostics.Write(StarBridge.HostRuntime.Auth.VisitorReadDiagnostics.Phase.Failed,
                code: failure is AccountBridgeHostException known ? known.Code : failure is OperationCanceledException ? "cancelled" : "other");
            throw;
        }
    }

    private async Task<PersonalProfileDocumentContract> ReadUserProfileCoreAsync(BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        var target = ParseAvatarTarget(payload);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException("profile.visitor_unavailable");
        var id = await ResolveAvatarAsync(target, session, FriendScope(context, generation), context, generation, token, profileRead: true);
        if (session.Scm is { } scm)
        {
            try
            {
                RequireSameRelaySession(session, RequireRelaySession(context));
                var historicalMember = target.Source == "community" && !id.StartsWith("scm-v1:", StringComparison.Ordinal);
                var profile = target.Source == "market"
                    ? await _oauth.LoadMarketTraderPersonalProfileAsync(scm,
                        long.Parse(id, System.Globalization.CultureInfo.InvariantCulture), token)
                    : historicalMember
                    ? await _oauth.LoadLegacyMemberVisitorPersonalProfileAsync(scm, id, token)
                    : await _oauth.LoadVisitorPersonalProfileAsync(scm, id, token);
                token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
                RequireSameSession(scm, RequireSession(context));
                RequireSameSession(scm, profile.ActiveSession);
                _session = profile.ActiveSession;
                // Finish all decoration waits before the final session and target
                // rechecks. A restricted public header is still an authorized read.
                var decorated = profile.Restricted is null
                    ? await WithVisitorLogoAsync(profile.Profile, token)
                    : null;
                var restrictedHeader = profile.Restricted is { } header
                    ? await WithOwnerOffsetAsync(header, token)
                    : null;
                // Only a member reached by id from the hall can be matched against this viewer's own trades.
                if (restrictedHeader is { NameMasked: true } && target.Source == "market")
                    restrictedHeader = await WithTradedHandleAsync(restrictedHeader, profile.ActiveSession,
                        long.Parse(id, System.Globalization.CultureInfo.InvariantCulture), context, generation, token);
                token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
                RequireSameSession(scm, RequireSession(context));
                if (target.Source is "communityApplicant" or "officialFleet" or "market" || historicalMember)
                {
                    // Profile permission and current review authority are independent. A slow
                    // Java response must not outlive withdrawal or review permission revocation.
                    var active = RequireRelaySession(context);
                    var currentId = await ResolveAvatarAsync(target, active, FriendScope(context, generation), context, generation, token, profileRead: true);
                    token.ThrowIfCancellationRequested();
                    if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
                    RequireSameRelaySession(active, RequireRelaySession(context));
                    if (!string.Equals(id, currentId, StringComparison.Ordinal))
                        throw new AccountBridgeHostException("profile.visitor_unavailable");
                }
                // Only after every session and target recheck above: the public header is still a read.
                if (restrictedHeader is not null)
                    throw new PersonalProfileRestrictedException(restrictedHeader);
                return decorated!;
            }
            catch (System.Net.Http.HttpRequestException e) when (e.StatusCode is System.Net.HttpStatusCode.NotFound or System.Net.HttpStatusCode.Forbidden)
            { throw new AccountBridgeHostException("profile.visitor_not_visible"); }
            catch (StarBridge.HostRuntime.Auth.ScmApiAuthenticationException)
            { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
            catch (StarBridge.HostRuntime.Auth.ScmApiRateLimitException) when (target.Source == "market")
            { throw new AccountBridgeHostException("profile.visitor_rate_limited", retryable: true); }
            catch (Exception e) when (e is System.Net.Http.HttpRequestException or System.IO.IOException or JsonException or ArgumentException or StarBridge.HostRuntime.Auth.ScmApiProtocolException)
            { throw new AccountBridgeHostException(AccountBridgeStableErrors.PersonalProfileReadUnavailable, retryable: true); }
        }
        if (session.Legacy is null || _legacyPasswordLogin is null)
            throw new AccountBridgeHostException("profile.visitor_unavailable");
        var result = await SendRelayRequestAsync(session,
            (active, ct) => _legacyPasswordLogin.ReadVisitorProfileAsync(active.Legacy!, id, ct), token);
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(session, RequireRelaySession(context));
        var decoratedLegacy = await WithVisitorLogoAsync(result.Result, token);
        token.ThrowIfCancellationRequested();
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(session, RequireRelaySession(context));
        if (target.Source == "communityApplicant")
        {
            var active = RequireRelaySession(context);
            var currentId = await ResolveAvatarAsync(target, active, FriendScope(context, generation), context, generation, token, profileRead: true);
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(active, RequireRelaySession(context));
            if (!string.Equals(id, currentId, StringComparison.Ordinal))
                throw new AccountBridgeHostException("profile.visitor_unavailable");
        }
        return decoratedLegacy;
    }

    public async Task<FriendsView> ReadUserSocialAsync(BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        var target = ParseAvatarTarget(payload);
        if (target.Source is "officialFleet" or "market") throw new AccountBridgeHostException("users.social_unavailable");
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
