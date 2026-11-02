using System.Text.Json;
using StarBridge.HostRuntime.Privacy;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private PrivacyRelayWriter? _privacyWriter;
    private readonly SemaphoreSlim _publicationLane = new(1, 1);
    private CancellationTokenSource? _communityPrivacyRead;
    internal void ConfigurePrivacyWriter(PrivacyRelayWriter writer) => _privacyWriter = writer;

    public async Task<CommunitySharingTargets> ReadCommunitySharingTargetsAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, long generation, CancellationToken token)
    {
        await using var admission = await _mutationGate.EnterSharedAsync(token).ConfigureAwait(false);
        var callerToken = token;
        using var readCancellation = CancellationTokenSource.CreateLinkedTokenSource(token);
        Interlocked.Exchange(ref _communityPrivacyRead, readCancellation);
        token = readCancellation.Token;
        try
        {
            if (_disposed || Generation != generation || GameplayTimeContext != owner)
                throw new AccountBridgeHostException("privacy_publication.account_changed");
            token.ThrowIfCancellationRequested();
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
            CommitSharingSession(session, result.ActiveSession);
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
        catch (OperationCanceledException) when (readCancellation.IsCancellationRequested && !callerToken.IsCancellationRequested)
        { throw new AccountBridgeHostException("privacy_publication.temporarily_unavailable", retryable: true); }
        finally
        {
            Interlocked.CompareExchange(ref _communityPrivacyRead, null, readCancellation);
        }
    }

    internal Action<string, string, int?, long>? PrivacyPublicationDiagnostic { get; set; }

    private async Task<IAsyncDisposable> WaitForPrivacyPublicationAsync(
        PrivacyPublicationInput input, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (_disposed || Generation != input.Generation || GameplayTimeContext != input.Owner)
            throw new AccountBridgeHostException("privacy_publication.account_changed");
        await _publicationLane.WaitAsync(token).ConfigureAwait(false);
        try
        {
            return await _mutationGate.EnterSharedAsync(token).ConfigureAwait(false);
        }
        catch
        {
            _publicationLane.Release();
            throw;
        }
    }

    public async Task PublishPrivacyAsync(PrivacyPublicationInput input, JsonElement payload, CancellationToken token)
        => await PublishPrivacyAsync(input, payload, token, null).ConfigureAwait(false);

    internal async Task PublishPrivacyAsync(PrivacyPublicationInput input, JsonElement payload,
        CancellationToken token, Action? current)
    {
        // Serialize this publication stream without blocking other sharing
        // domains. Account mutations retain exclusive admission.
        token.ThrowIfCancellationRequested();
        if (_disposed || Generation != input.Generation || GameplayTimeContext != input.Owner)
            throw new AccountBridgeHostException("privacy_publication.account_changed");
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var phase = "publication-gate";
        void Record(Exception? error = null)
        {
            var code = error switch {
                null => "ok", AccountBridgeHostException e => e.Code,
                OperationCanceledException => "cancelled", HttpRequestException => "network", _ => "unclassified"
            };
            var status = error is AccountBridgeHostException { HttpStatus: { } http } ? (int?)http : null;
            try { PrivacyPublicationDiagnostic?.Invoke(phase, code, status, watch.ElapsedMilliseconds); }
            catch { /* [DEBUG-community-read] Evidence cannot affect publication. */ }
            watch.Restart();
        }
        IAsyncDisposable priority;
        try { priority = await WaitForPrivacyPublicationAsync(input, token).ConfigureAwait(false); }
        catch (Exception error) { Record(error); throw; }
        await using var publicationPriority = priority;
        Record();
        phase = "publication-identity";
        try
        {
            // Retirement of the original positive-write lease is cancellation,
            // not revocation of the user's saved sharing consent. Recheck the
            // actual admission before interpreting a closed identity gate.
            token.ThrowIfCancellationRequested();
            current?.Invoke();
            if (_disposed || Generation != input.Generation || GameplayTimeContext != input.Owner)
                throw new AccountBridgeHostException("privacy_publication.account_changed");
            var session = RequireRelaySession(input.Owner);
            var identity = HangarIdentity?.Identity;
            var expected = identity is null ? null : StarBridge.Core.Hangar.RsiHangarIdentityPolicy.DisplayHandle(identity);
            var officialChoice = payload.TryGetProperty("officialFleet", out var rawOfficial)
                ? rawOfficial.Deserialize<StarBridge.Core.Presence.OfficialFleetRealtimeChoice>(LocalPrivacyStore.Json) : null;
            if (!OfficialRealtimeEnabled && payload.GetProperty("online").GetBoolean() && officialChoice is { Fields: not 0 } &&
                (payload.GetProperty("appPresenceConfirmed").GetBoolean() || payload.GetProperty("gameObserved").GetBoolean()))
                throw new AccountBridgeHostException("official_fleet.runtime_unavailable");
            var officialAppOnly = PrivacyPublicationPayload.IsOfficialAppOnly(payload);
            if ((expected ?? "") != input.Handle) throw new AccountBridgeHostException("privacy_publication.account_changed");
            if (officialAppOnly && payload.GetProperty("online").GetBoolean() &&
                !HasObservedAppPresence(input))
                throw new AccountBridgeHostException("privacy_publication.identity_required");
            if (payload.GetProperty("online").GetBoolean() && !officialAppOnly &&
                !(await GetGameIdentityPolicyAsync(input.Owner, token)).SensitiveWritesAllowed)
                throw new AccountBridgeHostException("privacy_publication.identity_required");
            var writer = _privacyWriter ?? throw new AccountBridgeHostException("privacy_publication.unavailable");
            Record();
            phase = "publication-send";
            var result = await SendRelayRequestAsync(session, async (active, ct) => {
                // OAuth can physically rotate its credential before invoking
                // this callback. Adopt that exact verified result, not a loose
                // same-subject/token exemption in installed business admission.
                if (_disposed || Generation != input.Generation || CurrentContext != input.Owner)
                    throw new AccountBridgeHostException("privacy_publication.account_changed");
                RequireSameRelaySession(RequireRelaySession(input.Owner), session);
                if (IsFirstUseAuthenticationCandidate && active.Scm is { } refreshed && session.Scm is { } original &&
                    (refreshed.AuthoritativeGameIdentity != original.AuthoritativeGameIdentity ||
                     !_oauth.IsInstalledFirstUseSessionCurrent(refreshed)))
                    throw new AccountBridgeHostException("privacy_publication.account_changed");
                CommitSharingSession(session, active);
                current?.Invoke();
                if (_disposed || Generation != input.Generation || GameplayTimeContext != input.Owner)
                    throw new AccountBridgeHostException("privacy_publication.account_changed");
                await writer.SendAsync(active.AccessToken, payload, ct, current ?? input.RequirePositiveAdmission,
                    allowOfficialPositive: OfficialRealtimeEnabled, admission: input.PositiveAdmission).ConfigureAwait(false);
                return true;
            }, token, privacyPublication: true).ConfigureAwait(false);
            if (_disposed || Generation != input.Generation) throw new AccountBridgeHostException("privacy_publication.account_changed");
            RequireSameRelaySession(RequireRelaySession(input.Owner), result.ActiveSession);
            CommitSharingSession(session, result.ActiveSession);
            Record();
        }
        catch (Exception error) { Record(error); throw; }
        finally { _publicationLane.Release(); }
    }

    internal bool HasObservedAppPresence(PrivacyPublicationInput input)
    {
        var snapshot = ReadObservedPublicationVisibility();
        return snapshot is { Observation: 1 or 2 } &&
            snapshot.Owner == input.Owner && snapshot.Generation == input.Generation;
    }
}
