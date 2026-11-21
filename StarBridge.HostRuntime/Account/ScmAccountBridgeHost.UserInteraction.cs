using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly PublicOrganizationLogoReader _publicOrganizationLogos;

    // A non-null affiliation on an authorized visitor document is the server's
    // visibility projection. Never recover hidden affiliations from other sources.
    // The owner's own page gets the same mark (user 11-11: one rail for everyone).
    // The SCM document leaves Kind empty for the main fleet; only communities
    // are marked, matching how the client reads it. The logo is decoration:
    // wait briefly, then show the page without it (the cache fills for next time).
    private async Task<PersonalProfileDocumentContract> WithFleetLogoAsync(
        PersonalProfileDocumentContract profile, CancellationToken token)
    {
        if (profile.FleetAffiliation is not { } affiliation ||
            affiliation.Kind is not (null or "officialFleet") ||
            !string.IsNullOrWhiteSpace(affiliation.LogoImageData)) return profile;
        var pending = _publicOrganizationLogos.ReadAsync(affiliation.FleetCode);
        var finished = await Task.WhenAny(pending, Task.Delay(VisitorLogoWait, token)).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        var logo = finished == pending ? await pending.ConfigureAwait(false) : null;
        return logo is null ? profile : profile with { FleetAffiliation = affiliation with { LogoUrl = logo.Image } };
    }

    // The owner's read and save wait for the mark too, so the same session and
    // generation checks run again after that wait (CX-PROFILE-HEADER-073-R).
    private async Task<PersonalProfileDocumentContract> OwnPageWithFleetLogoAsync(
        PersonalProfileDocumentContract profile, ScmOAuthSession session, BridgeAccountContext context,
        long generation, CancellationToken token)
    {
        var decorated = await WithFleetLogoAsync(profile, token);
        token.ThrowIfCancellationRequested();
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameSession(session, RequireSession(context));
        return decorated;
    }

    private static readonly TimeSpan VisitorLogoWait = TimeSpan.FromSeconds(2);

    private async Task<PersonalProfileTradeWindow?> FullPageTradeWindowAsync(
        System.Text.Json.JsonElement? raw, CancellationToken token)
    {
        PersonalProfileTradeWindow? window;
        try { window = raw is { } value ? PersonalProfileTradeWindow.Parse(value) : null; }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException) { return null; }
        if (window is null) return null;
        // An optional decoration on a page already read: a slow zone directory only
        // leaves the owner's offset out (the client then shows the owner's own setting).
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(VisitorAccountFactsBudget);
        IReadOnlyList<ScmTimeZoneDirectoryEntry> zones;
        try { zones = await PublicFactZonesAsync(budget.Token); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { zones = []; }
        return window with { OwnerOffsetMinutes = PublicFactOffset(zones, window.TimezoneId) };
    }

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

    public async Task<VisitorPersonalProfileResult> ReadUserProfileAsync(BridgeAccountContext context,
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

    private async Task<VisitorPersonalProfileResult> ReadUserProfileCoreAsync(BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        var target = ParseAvatarTarget(payload);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_credentialTemporarilyUnavailable && !_reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CredentialTemporarilyUnavailable, retryable: true);
        if (_reauthorizationRequired)
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
                    ? await WithFleetLogoAsync(profile.Profile, token)
                    : null;
                // HK swap 5: the always-public trade window of a full page. A missing, older or
                // malformed one only leaves the window out; it never fails the page.
                var tradeWindow = decorated is not null
                    ? await FullPageTradeWindowAsync(decorated.TradeWindow, token)
                    : null;
                // The facts endpoint does not enforce page visibility. Only a
                // successful full visitor read authorizes this optional request.
                var accountFacts = profile.Restricted is null && !historicalMember
                    ? await ReadVisitorAccountFactsAsync(profile.ActiveSession, id, target.Source == "market", token)
                    : null;
                var restrictedHeader = profile.Restricted is { } header
                    ? await WithOwnerOffsetAsync(header, token)
                    : null;
                // User 11-05: last online follows the online-status privacy, shown only on the
                // server's explicit yes. A never-saved page's header facts carry no such flag, so
                // its day comes from account-facts (already public for this page, decided 11-08);
                // any other header, a legacy member or a failed read shows none.
                if (restrictedHeader is { Facts: { LastOnlineDay: not null } headerFacts })
                {
                    var lastOnline = restrictedHeader.Defaulted && !historicalMember
                        ? (await ReadVisitorAccountFactsAsync(profile.ActiveSession, id, target.Source == "market", token))?.LastOnlineDay
                        : null;
                    restrictedHeader = restrictedHeader with { Facts = headerFacts with { LastOnlineDay = lastOnline } };
                }
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
                return new(decorated!, accountFacts, tradeWindow);
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
        var decoratedLegacy = await WithFleetLogoAsync(result.Result, token);
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
        return new(decoratedLegacy);
    }

    public async Task<FriendsView> ReadUserSocialAsync(BridgeAccountContext context,
        JsonElement payload, CancellationToken token)
    {
        var target = ParseAvatarTarget(payload);
        if (target.Source is "officialFleet" or "market") throw new AccountBridgeHostException("users.social_unavailable");
        var session = RequireRelaySession(context); var generation = Generation;
        if (_credentialTemporarilyUnavailable && !_reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CredentialTemporarilyUnavailable, retryable: true);
        if (_reauthorizationRequired)
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
