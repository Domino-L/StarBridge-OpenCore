using System.Text.Json;
using StarBridge.HostRuntime.Privacy;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private PrivacyRelayWriter? _privacyWriter;
    internal void ConfigurePrivacyWriter(PrivacyRelayWriter writer) => _privacyWriter = writer;

    public async Task<CommunitySharingTargets> ReadCommunitySharingTargetsAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, long generation, CancellationToken token)
    {
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (_disposed || Generation != generation || GameplayTimeContext != owner)
                throw new AccountBridgeHostException("privacy_publication.account_changed");
            var writer = _privacyWriter ?? throw new AccountBridgeHostException("privacy_publication.community_scopes_unavailable");
            var session = RequireRelaySession(owner);
            var result = await SendRelayRequestAsync(session, async (active, ct) => {
                if (_disposed || Generation != generation || GameplayTimeContext != owner)
                    throw new AccountBridgeHostException("privacy_publication.account_changed");
                return await writer.ReadCommunityTargetsAsync(active.AccessToken, ct).ConfigureAwait(false);
            }, token).ConfigureAwait(false);
            if (_disposed || Generation != generation || GameplayTimeContext != owner)
                throw new AccountBridgeHostException("privacy_publication.account_changed");
            RequireSameRelaySession(RequireRelaySession(owner), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            // Reuse already-authorized directory images; no per-card network reads.
            // Keep the complete settings response below the Bridge frame budget.
            var logoBudget = 512 * 1024;
            return result.Result with { Communities = result.Result.Communities.Select(row => {
                var logo = _communities?.CachedSharingLogo(FriendScope(owner, generation), row.Code);
                if (logo is null || logo.Length > logoBudget) return row with { LogoImageData = null };
                logoBudget -= logo.Length;
                return row with { LogoImageData = logo };
            }).ToArray() };
        }
        finally { _mutationGate.Release(); }
    }

    public async Task PublishPrivacyAsync(PrivacyPublicationInput input, JsonElement payload, CancellationToken token)
    {
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (_disposed || Generation != input.Generation || GameplayTimeContext != input.Owner)
                throw new AccountBridgeHostException("privacy_publication.account_changed");
            var session = RequireRelaySession(input.Owner);
            var identity = HangarIdentity?.Identity;
            var expected = identity is null ? null : StarBridge.Core.Hangar.RsiHangarIdentityPolicy.DisplayHandle(identity);
            if (expected != input.Handle) throw new AccountBridgeHostException("privacy_publication.account_changed");
            if (payload.GetProperty("online").GetBoolean() &&
                !(await GetGameIdentityPolicyAsync(input.Owner, token)).SensitiveWritesAllowed)
                throw new AccountBridgeHostException("privacy_publication.identity_required");
            var writer = _privacyWriter ?? throw new AccountBridgeHostException("privacy_publication.unavailable");
            var result = await SendRelayRequestAsync(session, async (active, ct) => {
                if (_disposed || Generation != input.Generation || GameplayTimeContext != input.Owner)
                    throw new AccountBridgeHostException("privacy_publication.account_changed");
                await writer.SendAsync(active.AccessToken, payload, ct).ConfigureAwait(false);
                return true;
            }, token).ConfigureAwait(false);
            if (_disposed || Generation != input.Generation) throw new AccountBridgeHostException("privacy_publication.account_changed");
            RequireSameRelaySession(RequireRelaySession(input.Owner), result.ActiveSession);
            _session = result.ActiveSession.Scm;
        }
        finally { _mutationGate.Release(); }
    }
}
