using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<StarBridge.Core.Profiles.PersonalProfileDocumentContract> ReadMemberPersonalProfileAsync(
        BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        if (session.Legacy is null || _legacyPasswordLogin is null || _communities is null)
            throw new AccountBridgeHostException("profile.visitor_unavailable");
        var target = _communities.ResolveVisitorProfileTarget(payload, FriendScope(context, generation), session.Legacy.AccountId);
        var result = await SendRelayRequestAsync(session,
            (active, ct) => _legacyPasswordLogin.ReadVisitorProfileAsync(active.Legacy!, target, ct), token);
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(session, RequireRelaySession(context));
        return result.Result;
    }

    public Task<object> PreviewCommunityInviteAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityInviteAsync(context, payload, false, token);
    public Task<object> AcceptCommunityInviteAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityInviteAsync(context, payload, true, token);
    private async Task<object> CommunityInviteAsync(BridgeAccountContext context, JsonElement payload, bool accept, CancellationToken token)
    {
        if (accept) CommunityClient.ParseInviteAcceptance(payload); else CommunityClient.ParseInvitePreview(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) => accept
            ? await client.AcceptInviteAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct)
            : await client.PreviewInviteAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct,
                wpfS2: active.Legacy is not null), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }

    public Task<object> ReadCommunityWorkspaceAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        ReadCommunitySurfaceAsync(context, payload, "workspace", token);
    public Task<object> ReadCommunityLogsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        ReadCommunitySurfaceAsync(context, payload, "logs", token);
    public Task<object> ReadCommunityMediaAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        ReadCommunitySurfaceAsync(context, payload, "media", token);
    public Task<object> ReadCommunityProfileAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        ReadCommunitySurfaceAsync(context, payload, "profile", token);
    public Task<object> ReadCommunityRolesAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityRolesAsync(context, payload, false, token);
    public Task<object> ReadCommunityMemberRoleAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityMemberRoleAsync(context, payload, false, token);
    public Task<object> ReadCommunityMemberRemovalAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityMemberRemovalAsync(context, payload, false, token);
    public Task<object> RemoveCommunityMemberAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityMemberRemovalAsync(context, payload, true, token);
    private async Task<object> CommunityMemberRemovalAsync(BridgeAccountContext context, JsonElement payload, bool remove, CancellationToken token)
    {
        if (remove) CommunityClient.ValidateMemberRemoval(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) => active.Legacy is not null
            ? remove ? await client.WriteWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "remove", Current, ct)
                : await client.ReadWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "remove", Current, ct)
            : remove
            ? await client.RemoveMemberAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct)
            : await client.ReadMemberRemovalAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
    public Task<object> SaveCommunityMemberRoleAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityMemberRoleAsync(context, payload, true, token);
    private async Task<object> CommunityMemberRoleAsync(BridgeAccountContext context, JsonElement payload, bool save, CancellationToken token)
    {
        if (save) CommunityClient.ValidateMemberRoleSave(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) => active.Legacy is not null
            ? save ? await client.WriteWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "role", Current, ct)
                : await client.ReadWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "role", Current, ct)
            : save
            ? await client.SaveMemberRoleAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct)
            : await client.ReadMemberRoleAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
    public Task<object> SaveCommunityRolesAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityRolesAsync(context, payload, true, token);
    private async Task<object> CommunityRolesAsync(BridgeAccountContext context, JsonElement payload, bool save, CancellationToken token)
    {
        if (save) CommunityClient.ValidateRolesSave(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) => active.Legacy is not null
            ? save ? await client.WriteWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "roles", Current, ct)
                : await client.ReadWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "roles", Current, ct)
            : save
            ? await client.SaveRolesAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct)
            : await client.ReadRolesAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
    public async Task<object> ReadCommunityAdmissionsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
        => await CommunityAdmissionsAsync(context, payload, false, token);
    public async Task<object> ManageCommunityAdmissionsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
        => await CommunityAdmissionsAsync(context, payload, true, token);
    private async Task<object> CommunityAdmissionsAsync(BridgeAccountContext context, JsonElement payload, bool manage, CancellationToken token)
    {
        if (manage) CommunityClient.ParseAdmissionIntent(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) => manage
            ? await client.ManageAdmissionsAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct,
                wpfS2: active.Legacy is not null)
            : await client.ReadAdmissionsAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct,
                wpfS2: active.Legacy is not null), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
    private async Task<object> ReadCommunitySurfaceAsync(BridgeAccountContext context, JsonElement payload, string surface, CancellationToken token)
    {
        var session = RequireRelaySession(context);
        var generation = Generation;
        var sequence = Interlocked.Increment(ref _playerActivitySequence);
        Notifications.PlayerActivitySourceSnapshot? activity = null;
        Action<Notifications.PlayerActivitySourceSnapshot>? observed = ObservePlayerActivity() ? value => activity = value : null;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync(session,
            (active, ct) => surface switch
            {
                "media" => client.ReadMediaAsync(active.AccessToken, payload, FriendScope(context, generation), ct),
                "logs" => active.Legacy is not null
                    ? client.ReadWpfS2LogsAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct)
                    : client.ReadLogsAsync(active.AccessToken, payload, FriendScope(context, generation), ct),
                "profile" => active.Legacy is { } legacy
                    ? client.ReadWpfS2ProfileAsync(active.AccessToken, payload, FriendScope(context, generation),
                        legacy.AccountId, ct)
                    : client.ReadProfileAsync(active.AccessToken, payload, FriendScope(context, generation), ct),
                _ => client.ReadWorkspaceAsync(active.AccessToken, payload, FriendScope(context, generation), ct, observed)
            }, token);
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
        _session = result.ActiveSession.Scm;
        PublishPlayerActivity(context, generation, sequence, activity);
        return result.Result;
    }

    public Task<object> GetCommunityCreationOptionsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        RequireRelaySession(context);
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        return Task.FromResult(CommunityClient.CreationOptions(payload));
    }

    public async Task<object> SaveCommunityProfileAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        CommunityClient.ValidateProfileSave(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync(session,
            (active, ct) => active.Legacy is { } legacy
                ? client.SaveWpfS2ProfileAsync(active.AccessToken, payload, FriendScope(context, generation),
                    legacy.AccountId, Current, ct)
                : client.SaveProfileAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        if (result.Result is { Status: "accepted", OrganizationCode: { } code, OrganizationName: { } name })
            CommunityNameChanged?.Invoke(context, generation, code, name);
        return result.Result;
    }

    internal Action<BridgeAccountContext, long, string, string>? CommunityNameChanged { get; set; }

    public async Task<object> CreateCommunityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        CommunityClient.ParseCreation(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync(session, (active, ct) =>
        {
            if (active.Legacy is not { } legacy)
                return client.CreateAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct);
            var gameName = _legacyIdentity?.Status == StarBridge.Core.Identity.ScmGameIdentityStatus.Verified
                ? _legacyIdentity.Handle?.Trim()
                : null;
            if (string.IsNullOrWhiteSpace(gameName))
                throw new AccountBridgeHostException("communities.identityRequired");
            var callsign = _legacyDisplayName?.Trim();
            var commander = string.IsNullOrWhiteSpace(callsign) ||
                            callsign.Equals(gameName, StringComparison.OrdinalIgnoreCase)
                ? gameName
                : $"{callsign} ({gameName})";
            return client.CreateWpfS2Async(active.AccessToken, payload, FriendScope(context, generation),
                legacy.AccountId, commander, Current, ct);
        }, token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }

    public async Task<object> ReadCommunitiesAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var query = CommunityClient.ParseQuery(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        var sequence = Interlocked.Increment(ref _playerActivitySequence);
        Notifications.PlayerActivitySourceSnapshot? activity = null;
        Action<Notifications.PlayerActivitySourceSnapshot>? observed = ObservePlayerActivity() ? value => activity = value : null;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var result = await SendRelayRequestAsync(session,
            (active, ct) => active.Legacy is { } legacy
                ? client.ReadWpfS2Async(active.AccessToken, query, FriendScope(context, generation), legacy.AccountId, ct, observed)
                : client.ReadAsync(active.AccessToken, query, FriendScope(context, generation), ct), token);
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
        _session = result.ActiveSession.Scm;
        PublishPlayerActivity(context, generation, sequence, activity);
        return result.Result;
    }

    public async Task<object> ExecuteCommunityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        CommunityClient.ParseCommand(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync(session,
            (active, ct) => client.ExecuteAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
