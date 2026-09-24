using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> PreviewCommunityInviteSendAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        InvitationSendAsync(context, payload, "preview", token);
    public Task<object> SendCommunityInviteAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        InvitationSendAsync(context, payload, "send", token);
    public Task<object> ResumeCommunityInviteAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        InvitationSendAsync(context, payload, "resume", token);
    public Task<object> ReadCommunityInvitationOutboxAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        InvitationSendAsync(context, payload, "read", token);

    private async Task<object> InvitationSendAsync(BridgeAccountContext context, JsonElement payload, string operation, CancellationToken token)
    {
        InvitationSendRequest? send = null;
        (string OperationId, string Action) resume = ("", "");
        if (operation == "preview") send = InvitationBridgeRequests.Preview(payload);
        else if (operation == "read") InvitationBridgeRequests.Read(payload);
        else if (operation == "resume") resume = InvitationBridgeRequests.Resume(payload);
        else send = InvitationBridgeRequests.Send(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var accountKey = JsonSerializer.Serialize(context);
        var scope = FriendScope(context, generation);
        void Current()
        {
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        try
        {
            Current();
            if (operation == "read")
            {
                var page = await client.ReadInvitationOutboxAsync(accountKey);
                Current();
                return page;
            }
            var outcome = await SendRelayRequestAsync<object>(session, async (active, ct) =>
            {
                string sourceRef, id, action;
                int maxUses;
                InvitationDeliveryTarget destination;
                if (send is not null)
                {
                    sourceRef = send.OrganizationRef; id = send.OperationId; maxUses = send.MaxUses; action = send.Action;
                    destination = send.Channel == "private"
                        ? (_friends ?? throw new AccountBridgeHostException("directMessages.unavailable")).ResolveInvitationTarget(active.AccessToken, send.DestinationRef, scope)
                        : await (_partyRooms ?? throw new AccountBridgeHostException("party_rooms.unavailable"))
                            .ResolveInvitationTargetAsync(active.AccessToken, send.DestinationRef, scope, Current, ct);
                }
                else
                {
                    id = resume.OperationId; action = resume.Action;
                    var pending = await client.FindInvitationOperationAsync(accountKey, id);
                    Current();
                    if (pending is null) return new InvitationSendProgress(id, "unknown", "notFound");
                    if (pending.Phase == "sent") return new InvitationSendProgress(id, "sent");
                    maxUses = pending.MaxUses;
                    sourceRef = active.Legacy is { } legacy
                        ? await client.RebindWpfS2InvitationSourceAsync(
                            active.AccessToken, pending, scope, legacy.AccountId, Current, ct)
                        : await client.RebindInvitationSourceAsync(active.AccessToken, pending, scope, Current, ct);
                    destination = pending.Channel == "private"
                        ? await (_friends ?? throw new AccountBridgeHostException("directMessages.unavailable"))
                            .RebindInvitationTargetAsync(active.AccessToken, pending.DestinationId, scope, ct)
                        : await (_partyRooms ?? throw new AccountBridgeHostException("party_rooms.unavailable"))
                            .ResolveInvitationTargetAsync(active.AccessToken, pending.DestinationId, scope, Current, ct);
                }
                Current();
                if (active.Legacy is { } legacySession)
                {
                    if (operation == "preview")
                        return await client.PreviewWpfS2InvitationTargetAsync(active.AccessToken, sourceRef, destination,
                            scope, legacySession.AccountId, Current, ct);
                    return await client.AdvanceWpfS2InvitationSendAsync(active.AccessToken, accountKey, id, sourceRef,
                        destination, maxUses, action, scope, legacySession.AccountId, Current, ct);
                }
                if (operation == "preview")
                    return await client.PreviewInvitationTargetAsync(active.AccessToken, sourceRef, destination, scope, Current, ct);
                return await client.AdvanceInvitationSendAsync(active.AccessToken, accountKey, id, sourceRef,
                    destination, maxUses, action, scope, Current, ct);
            }, token);
            Current(); _session = outcome.ActiveSession.Scm;
            return outcome.Result;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or CryptographicException or JsonException)
        { throw new AccountBridgeHostException("communities.localRecoveryUnavailable"); }
    }
}
