using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private async Task<IReadOnlyDictionary<long, OfficialFleetMemberIdentityObservation>> ReadFleetIdentityObservationsAsync(
        BridgeAccountContext owner, long generation, string sourceRef, IReadOnlyCollection<long> ids, CancellationToken token)
    {
        try
        {
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(owner, generation);
            if (ids.Count == 0) return new Dictionary<long, OfficialFleetMemberIdentityObservation>();
            var session = RequireSession(owner);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.G1Read);
            var result = await _oauth.ReadOfficialFleetMemberIdentityObservationsAsync(session, sourceRef, ids, token);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(owner, generation);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            OfficialFleetMemberIdentityObservation.EnsureCurrent(result.Result.Values,
                _oauth.OfficialFleetIdentityObservationClock.GetUtcNow());
            return result.Result;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (ScmApiAuthenticationException error)
        {
            Privacy.OfficialMemberReadObservation.Failure(error);
            AccountReadTiming.G1Failure(error);
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
        catch (AccountBridgeHostException error) { AccountReadTiming.G1Failure(error); throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or
            System.Text.Json.JsonException or KeyNotFoundException or FormatException or OverflowException or
            OperationCanceledException or ArgumentException or TimeoutException)
        {
            Privacy.OfficialMemberReadObservation.Failure(error);
            AccountReadTiming.G1Failure(error);
            throw OfficialFleetMemberIdentity.Invalid();
        }
    }
}
