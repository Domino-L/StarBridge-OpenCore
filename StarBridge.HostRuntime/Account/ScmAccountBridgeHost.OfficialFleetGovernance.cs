using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record GovernanceSupport(long Generation, string SourceRef);
    private GovernanceSupport? _governanceSupport;
    internal IReadOnlyList<string> GovernanceCapabilities => !_disposed && !_reauthorizationRequired &&
        !_credentialTemporarilyUnavailable && Volatile.Read(ref _governanceSupport)?.Generation == Generation
        ? [AccountBridgeRequestNames.ActivateOfficialFleetGovernance, AccountBridgeRequestNames.RevokeOfficialFleetGovernanceActivation] : [];

    public async Task<object> ReadOfficialFleetGovernanceContextAsync(BridgeAccountContext context,
        JsonElement body, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        _ = RequireSession(context);
        var session = await ReadDirectRelaySessionAsync(context, deadline.Token).ConfigureAwait(false);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            deadline.Token.ThrowIfCancellationRequested();
            if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
            _ = RequireSession(context);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        Current();
        Volatile.Write(ref _governanceSupport, null);
        var roleSupportObserved = false;
        var result = await SendRelayRequestAsync<object>(session, (active, ct) =>
            client.ReadOfficialGovernanceContextAsync(active.AccessToken, body, Current, ct, () => roleSupportObserved = true), deadline.Token);
        Current();
        CommitSharingSession(session, result.ActiveSession);
        Current();
        if (roleSupportObserved && result.Result is JsonElement row)
            Volatile.Write(ref _governanceSupport, new(generation, row.GetProperty("sourceRef").GetString()!));
        Current();
        return result.Result;
    }

    public Task<object> ActivateOfficialFleetGovernanceAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        WriteGovernanceActivationAsync(context, body, true, token);
    public Task<object> RevokeOfficialFleetGovernanceActivationAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        WriteGovernanceActivationAsync(context, body, false, token);

    internal TimeSpan GovernanceWriteDeadline { get; set; } = TimeSpan.FromSeconds(12);

    private async Task<object> WriteGovernanceActivationAsync(BridgeAccountContext context, JsonElement body, bool activate, CancellationToken token)
    {
        var started = System.Diagnostics.Stopwatch.GetTimestamp();
        var activationCode = "no-session";
        int? activationStatus = null;
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(GovernanceWriteDeadline);
            _ = RequireSession(context);
            activationCode = "no-relay-session";
            RelayRequestSession session;
            try { session = await ReadDirectRelaySessionAsync(context, deadline.Token).ConfigureAwait(false); }
            catch (OperationCanceledException) when (!token.IsCancellationRequested)
            {
                // Nothing has reached the relay yet, so the caller must not keep this
                // as an uncertain write. Timeouts after sending stay uncertain below.
                activationCode = "not-sent";
                throw new AccountBridgeHostException("communities.activationNotSent", retryable: true);
            }
            var generation = Generation;
            if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            {
                activationCode = _reauthorizationRequired ? "reauthorization-required" : "credential-unavailable";
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            }
            activationCode = "communities-unavailable";
            var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
            void Current()
            {
                if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
                _ = RequireSession(context);
                RequireSameRelaySession(RequireRelaySession(context), session);
            }
            Current();
            activationCode = "data-invalid";
            var source = Communities.CommunityClient.ValidateGovernanceActivation(body);
            var support = Volatile.Read(ref _governanceSupport);
            if (support?.Generation != generation || support.SourceRef != source)
            {
                activationCode = "upgrade-required";
                throw new AccountBridgeHostException("communities.upgradeRequired");
            }
            // A mutation is sent once. In particular, uncertain transport outcomes must not
            // enter a refresh/retry loop; the caller keeps the original operation ID.
            activationCode = "not-sent";
            var result = await client.WriteGovernanceActivationAsync(session.AccessToken, body, activate, Current, deadline.Token,
                (code, status) => { activationCode = code; activationStatus = status; });
            Current();
            return result;
        }
        catch (BridgeStaleGenerationException) { activationCode = "stale-generation"; throw; }
        finally
        {
            RecordOfficialDiagnostic("official-governance-activation", activationCode, activationStatus,
                (long)System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds);
        }
    }
}
