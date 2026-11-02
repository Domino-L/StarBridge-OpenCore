using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly byte[] _fleetReferenceKey = RandomNumberGenerator.GetBytes(32);

    private async Task<AccountBridgeOfficialFleetSummary> AddOfficialFleetProfileAsync(
        AccountBridgeOfficialFleetSummary fleet, BridgeAccountContext context, long generation, CancellationToken token)
    {
        using var data = await _oauth.ReadPublicOrganizationAsync("get?sid=" + Uri.EscapeDataString(fleet.Sid), token);
        RequireFleetReadOwner(context, generation);
        return fleet with { Profile = OfficialFleetReadModel.Profile(data.RootElement, fleet.SourceRef, fleet.Sid) };
    }

    public Task<object> GetOfficialFleetMembersAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        ObserveOfficialMembers("official-members", context, payload, () => GetOfficialFleetMembersCoreAsync(context, payload, token));

    private async Task<object> GetOfficialFleetMembersCoreAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        try {
            if (payload.EnumerateObject().Any(item => item.Name is not ("schemaVersion" or "sourceRef" or "search" or "filter" or "pageNumber" or "pageSize")))
                throw OfficialFleetReadModel.Invalid();
            var sourceRef = payload.GetProperty("sourceRef").GetString();
            var search = payload.GetProperty("search").GetString();
            var page = payload.GetProperty("pageNumber").GetInt32();
            var size = payload.GetProperty("pageSize").GetInt32();
            if (sourceRef is null || search is null || search.Length > 128 || search.Any(char.IsControl) ||
                page is < 1 or > 100000 || size is not (25 or 50 or 100) || payload.GetProperty("filter").GetString() != "all")
                throw OfficialFleetReadModel.Invalid();
            var generation = Generation;
            using var data = await ReadOfficialFleetMemberPageSourceAsync(context, generation, sourceRef, search, page, size, token);
            var ids = data.RootElement.GetProperty("list").EnumerateArray()
                .Select(row => OfficialFleetPublicId.Read(row.GetProperty("userId"))).ToArray();
            var identities = await ReadFleetIdentitiesAsync(context, generation, sourceRef, ids, token);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(context, generation);
            RememberFleetProfileTargets(context, generation, sourceRef, identities);
            var self = await FindOfficialFleetSelfAsync(context, generation, identities, token);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(context, generation);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Materialize);
            return OfficialFleetReadModel.Members(data.RootElement, sourceRef, page, size, search,
                id => OfficialFleetMemberReference(generation, sourceRef, id), identities, self);
        }
        catch (OperationCanceledException error) when (token.IsCancellationRequested) { Privacy.OfficialMemberReadObservation.Failure(error); throw; }
        catch (AccountBridgeHostException) { throw; }
        catch (Auth.ScmApiAuthenticationException error) {
            Privacy.OfficialMemberReadObservation.Failure(error);
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or
            JsonException or InvalidDataException or KeyNotFoundException or FormatException or OperationCanceledException or OverflowException or TimeoutException) {
            Privacy.OfficialMemberReadObservation.Failure(error);
            throw OfficialFleetReadFailures.FromException(error, token);
        }
    }

    private async Task<JsonDocument> ReadOfficialFleetMemberPageSourceAsync(BridgeAccountContext context, long generation,
        string sourceRef, string search, int page, int size, CancellationToken token)
    {
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            var session = RequireSession(context);
            RequireFleetReadOwner(context, generation);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Bootstrap);
            var bootstrap = await _oauth.LoadBootstrapAsync(session, token);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(context, generation);
            RequireSameSession(session, bootstrap.ActiveSession);
            _session = bootstrap.ActiveSession;
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Bootstrap);
            var fleet = ProjectOfficialFleet(bootstrap.Snapshot, DateTimeOffset.UtcNow).Fleet;
            FleetMembershipObserved?.Invoke(context, generation, fleet?.SourceRef);
            if (fleet is null || fleet.SourceRef != sourceRef) throw OfficialFleetReadModel.Invalid();
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.RegisteredPage);
            var data = await _oauth.ReadPublicOrganizationAsync(
                $"member/page?organizationSid={Uri.EscapeDataString(fleet.Sid)}&keyword={Uri.EscapeDataString(search)}" +
                $"&pageNo={page.ToString(CultureInfo.InvariantCulture)}&pageSize={size.ToString(CultureInfo.InvariantCulture)}" +
                "&orderBy=join_time&orderDirection=asc", token);
            try {
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(context, generation);
            // Validate the public page before sending any source IDs to the
            // authenticated Java identity/visibility authority.
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Materialize);
            _ = OfficialFleetReadModel.Members(data.RootElement, sourceRef, page, size, search,
                id => OfficialFleetMemberReference(generation, sourceRef, id));
            return data;
            } catch { data.Dispose(); throw; }
    }

    private string OfficialFleetMemberReference(long generation, string sourceRef, long id) =>
        Convert.ToHexString(HMACSHA256.HashData(_fleetReferenceKey,
            Encoding.UTF8.GetBytes($"{generation}:{sourceRef}:{id}"))).ToLowerInvariant();

    private void RequireFleetReadOwner(BridgeAccountContext context, long generation)
    {
        if (_disposed || Generation != generation || CurrentContext != context ||
            _credentialTemporarilyUnavailable || _reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        _ = RequireSession(context);
    }
}
