using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

/// <summary>Real-time fields only. Inventory and event feeds keep their own consent/contracts.</summary>
internal sealed record PrivacyPublicationInput(BridgeAccountContext Owner, long Generation,
    string Handle, bool IdentityConfirmed, string? GameVersion, GameLogSessionSnapshot Game,
    bool AppAway = false);

internal sealed record PrivacyPublicationStatus(string State, long? AppliedRevision = null,
    DateTimeOffset? AppliedAt = null, string? ErrorCode = null, bool? FirstUseRequired = null)
{
    public int SchemaVersion => 1;
    public int SupportedFields => (int)PlayerSharedStateAudiencePolicy.PartyRoomLiveStateFields;
}

internal static class PrivacyPublicationPayload
{
    internal static JsonElement Build(PrivacyPublicationInput input, LocalPrivacySettings settings, bool clear, PlayerPresenceVisibilityMode visibility = PlayerPresenceVisibilityMode.Online)
    {
        var enabled = settings.PublicationEnabled && !clear &&
            visibility is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame;
        const PlayerSharedStateFields supported = PlayerSharedStateAudiencePolicy.PartyRoomLiveStateFields;
        var fleet = enabled && settings.Communities is null ? settings.Fleet.Fields & supported : PlayerSharedStateFields.None;
        var room = enabled ? settings.Room.Fields & supported : PlayerSharedStateFields.None;
        // Do not upload fields without any potential audience. Remote authorization
        // remains authoritative; a local group ID never grants membership.
        var effectiveFleet = settings.Fleet.AllMembersCanView || settings.Fleet.AdministratorsCanView
            ? fleet : PlayerSharedStateFields.None;
        var effectiveRoom = settings.Room.AllMembersCanView ? room : PlayerSharedStateFields.None;
        var communities = settings.Communities is null ? null : enabled
            ? CommunityRealtimeScope.ValidateAndCopy(settings.Communities) : [];
        var fields = effectiveFleet | effectiveRoom;
        foreach (var scope in communities ?? [])
            fields |= scope.PotentialFields;
        bool Has(PlayerSharedStateFields field) => fields.HasFlag(field);
        var playing = enabled && input.GameVersion is not null;
        var connected = playing && input.Game.Server.State == "connected";
        var ship = playing && Has(PlayerSharedStateFields.Ship) && input.Game.Ship.State == "confirmed"
            ? input.Game.Ship.EnglishName : null;
        var locationConfidence = input.Game.Location.State switch {
            "confirmed" => "High", "likely" => "Medium", "possible" => "Low", _ => "None"
        };
        var locationAvailable = connected && Has(PlayerSharedStateFields.Location) && input.Game.Location.CanSynchronize &&
            locationConfidence != "None" && !string.IsNullOrWhiteSpace(input.Game.Location.EnglishName);
        var locationHiddenByConfidence = locationAvailable && (settings.HideLowConfidenceLocation ?? true) &&
            locationConfidence is "Medium" or "Low";
        var location = locationAvailable && !locationHiddenByConfidence
            ? input.Game.Location.EnglishName : null;
        var online = enabled && fields != PlayerSharedStateFields.None;
        var payload = JsonSerializer.SerializeToElement(new {
            name = input.Handle, callsign = input.Handle, fleet = "No Fleet",
            online, ship = ship ?? "Unknown", shipConfidence = ship is null ? "None" : "High",
            location = location ?? "Unknown", locationConfidence = location is null ? "None" : locationConfidence,
            locationHiddenReason = locationHiddenByConfidence && !input.Game.Location.ArrivalPendingConfirmation ? "lowConfidence" : null,
            gameVersion = playing ? input.GameVersion : null,
            lastUpdated = DateTimeOffset.UtcNow,
            visibilityScope = "Private", roomVisibilityScope = "Private",
            fleetSharedStateFields = (int)fleet, roomSharedStateFields = (int)room,
            fleetAdministratorsCanView = enabled && communities is null && settings.Fleet.AdministratorsCanView,
            fleetMembersCanView = enabled && communities is null && settings.Fleet.AllMembersCanView,
            fleetVisibilityGroupIds = Array.Empty<string>(),
            roomMembersCanView = enabled && settings.Room.AllMembersCanView,
            roomVisibilityGroupIds = Array.Empty<string>(), allowedViewerAccountIds = Array.Empty<string>(),
            friendsCanViewPresence = false,
            serverShard = connected && Has(PlayerSharedStateFields.Server) ? input.Game.Server.Shard : null,
            serverRegion = connected && Has(PlayerSharedStateFields.Server) ? input.Game.Server.Region : null,
            liveStatus = !online ? "Offline" : visibility == PlayerPresenceVisibilityMode.InGame || playing ? "InGame" : input.AppAway ? "Away" : "AppOnline",
            arrivalPendingConfirmation = false, arrivalTargetCode = (string?)null
            // Only the scoped realtime route may consume this payload. Inventory,
            // its consent/audience and event feeds belong to separate publications.
        });
        if (communities is null) return payload;
        var body = System.Text.Json.Nodes.JsonNode.Parse(payload.GetRawText())!.AsObject();
        body["communities"] = JsonSerializer.SerializeToNode(communities, LocalPrivacyStore.Json);
        return JsonSerializer.SerializeToElement(body);
    }
}

/// <summary>
/// Account-scoped explicit consent + serialized latest-snapshot publication.
/// Saving local choices alone cannot activate sharing. No persisted payload queue.
/// </summary>
internal sealed class PrivacyPublication : IDisposable
{
    internal PrivacyPublicationStatus StatusFor(BridgeAccountContext owner)
    {
        var status = Status with { FirstUseRequired = _store.NeedsFirstChoice(owner) };
        if (status.State == "inactive" && _store.Read(owner).Settings?.PublicationEnabled == true)
            status = status with { ErrorCode = !_store.HasPublicationConsent(owner)
                ? "privacy_publication.consent_required" : _current() is null
                    ? "privacy_publication.identity_pending" : status.ErrorCode };
        return status;
    }

    private readonly LocalPrivacyStore _store;
    private readonly Func<PlayerPresenceVisibilityMode> _visibility;
    private readonly Func<PrivacyPublicationInput?> _current;
    private readonly Func<PrivacyPublicationInput, JsonElement, CancellationToken, Task> _send;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private readonly ITimer? _timer;
    private readonly TimeProvider _clock;
    private int _retryFailures;
    private DateTimeOffset _retryAfter;
    private long? _retryRevision;
    private PrivacyPublicationInput? _active;
    private bool _withdrawOnly;
    private PrivacyPublicationInput? _visibilitySuspended;
    // Only a recoverable transport failure can retain existing session consent.
    // This is not a payload queue: every retry rebuilds current fields/policy.
    private PrivacyPublicationInput? _recovery;
    private bool _restoreBlocked;
    private PrivacyPublicationStatus _status = new("inactive");
    private bool _disposed;
    private int _tickPending;

    internal PrivacyPublication(LocalPrivacyStore store, Func<PrivacyPublicationInput?> current,
        Func<PrivacyPublicationInput, JsonElement, CancellationToken, Task> send, bool startTimer = true,
        Func<PlayerPresenceVisibilityMode>? visibility = null, TimeProvider? timeProvider = null)
    {
        _store = store; _current = current; _send = send;
        _visibility = visibility ?? (() => PlayerPresenceVisibilityMode.Online);
        _clock = timeProvider ?? TimeProvider.System;
        if (startTimer) _timer = _clock.CreateTimer(_ => _ = TickAsync(), null,
            TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
    }
    internal PrivacyPublicationStatus Status => Volatile.Read(ref _status);
    internal Action<string, string?>? Diagnostic { get; set; }
    internal void Invalidate()
    {
        _active = null;
        _visibilitySuspended = null;
        _recovery = null;
        _restoreBlocked = false;
        _withdrawOnly = true;
        ResetRetry();
        Set(new("inactive"));
    }
    private bool Same(PrivacyPublicationInput a, PrivacyPublicationInput? b) =>
        b is not null && a.Owner == b.Owner && a.Generation == b.Generation && a.Handle == b.Handle;

    internal async Task<PrivacyPublicationStatus> ApplyAsync(BridgeAccountContext owner, long generation,
        long revision, CancellationToken cancellation)
    {
        await _gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            var input = _current();
            if (_disposed || input is null || input.Owner != owner || input.Generation != generation)
                throw new LocalPrivacyException("privacy_publication.account_changed");
            var saved = _store.Read(owner);
            if (saved.Settings is null || saved.Revision != revision)
                throw new LocalPrivacyException("privacy_publication.refresh_required");
            _store.SetPublicationConsent(owner, revision, saved.Settings.PublicationEnabled,
                () => !_disposed && Same(input, _current()));
            _recovery = null;
            _restoreBlocked = false;
            ResetRetry();
            // Remember the authenticated account's explicit choice, but wait for
            // verified game identity before starting any positive publication.
            if (!input.IdentityConfirmed && saved.Settings.PublicationEnabled)
                return Set(new("identityRequired"));
            _active = input;
            _withdrawOnly = false;
            await SendCurrentAsync(input, saved, cancellation).ConfigureAwait(false);
            return Status;
        }
        finally { ReleaseGate(); }
    }

    internal async Task TickAsync()
    {
        if (_disposed) return;
        Interlocked.Exchange(ref _tickPending, 1);
        if (!await _gate.WaitAsync(0).ConfigureAwait(false)) return;
        try
        {
            var passes = 0;
            do
            {
                Interlocked.Exchange(ref _tickPending, 0);
                await TickCoreAsync().ConfigureAwait(false);
                // Coalesce bursts, but yield to queued stop/save/visibility work.
            } while (++passes < 2 && !_disposed && Volatile.Read(ref _tickPending) != 0);
        }
        finally { ReleaseGate(); }
    }

    private void ReleaseGate()
    {
        _gate.Release();
        // Explicit apply/visibility changes must also drain pending input wakes.
        // Every pass rechecks current ownership, consent and game evidence.
        if (!_disposed && Volatile.Read(ref _tickPending) != 0) _ = TickAsync();
    }

    private async Task TickCoreAsync()
    {
        try
        {
            var active = _active;
            if (active is null && _recovery is { } recovery)
            {
                active = _active = recovery;
                _recovery = null;
                _withdrawOnly = false;
            }
            if (active is null && !_restoreBlocked && _current() is { } candidate &&
                _store.HasPublicationConsent(candidate.Owner))
            {
                if (!candidate.IdentityConfirmed && _visibility() is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame)
                { Set(new("identityRequired")); return; }
                active = _active = candidate;
                _withdrawOnly = false;
            }
            if (active is null) return;
            var input = _current();
            if (!Same(active, input)) { _active = null; Set(new("inactive")); return; }
            if (_withdrawOnly) await WithdrawAsync(active, _lifetime.Token).ConfigureAwait(false);
            else await SendCurrentAsync(input!, _store.Read(active.Owner), _lifetime.Token, background: true).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            // A corrupt/unreadable policy cannot keep the old published fields live.
            _recovery = null;
            _restoreBlocked = true;
            _withdrawOnly = true;
            if (_active is { } active && Same(active, _current()))
                await WithdrawAsync(active, _lifetime.Token).ConfigureAwait(false);
            if (Status.State != "withdrawalPending") Set(new("failed", ErrorCode: StableError(error)));
        }
    }

    private async Task SendCurrentAsync(PrivacyPublicationInput input, LocalPrivacySnapshot saved, CancellationToken cancellation,
        bool background = false)
    {
        var canResume = false;
        var acknowledged = Status;
        var stableHeartbeat = false;
        var sentVisibility = PlayerPresenceVisibilityMode.Online;
        try
        {
            var settings = saved.Settings ?? throw new LocalPrivacyException("privacy_publication.refresh_required");
            var consent = _store.HasPublicationConsent(input.Owner);
            var visibility = _visibility();
            sentVisibility = visibility;
            var invisible = visibility is not (PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame);
            var clear = !consent || !settings.PublicationEnabled || !input.IdentityConfirmed || invisible;
            // Input wakes cannot bypass transport backoff. Authority is checked
            // first: privacy clears and explicit actions are never delayed.
            if (background && !clear && _retryRevision == saved.Revision && _clock.GetUtcNow() < _retryAfter) return;
            canResume = consent && settings.PublicationEnabled && !invisible;
            if (clear) _recovery = null;
            // A heartbeat renews an acknowledged policy, not a user apply action.
            // Same-policy transport failures must not manufacture an Offline
            // write. Authority changes and explicit applies still fail closed.
            stableHeartbeat = background && !clear && acknowledged.AppliedAt is not null &&
                (acknowledged.State is "applied" or "reconnecting") && acknowledged.AppliedRevision == saved.Revision;
            if (!background || clear || acknowledged.State is not ("applied" or "reconnecting") ||
                acknowledged.State == "applied" && acknowledged.AppliedRevision != saved.Revision)
                Set(new("publishing"));
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _lifetime.Token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            // Game and identity fields come from Host evidence. The only UI
            // observation is the account-scoped, boolean app inactivity state.
            await _send(input, PrivacyPublicationPayload.Build(input, settings, clear, visibility), deadline.Token).ConfigureAwait(false);
            if (!Same(input, _current())) { _active = null; Set(new("inactive")); return; }
            if (_store.Read(input.Owner).Revision != saved.Revision)
            { Set(new("pending")); return; }
            ResetRetry();
            Set(new(clear ? "withdrawn" : "applied", saved.Revision, _clock.GetUtcNow()));
            // Successful invisible clear stops even empty periodic snapshots.
            if (invisible || !consent || !settings.PublicationEnabled)
            { _active = null; _restoreBlocked = true; }
        }
        catch (Exception error)
        {
            if (Recoverable(error)) ScheduleRetry(saved.Revision);
            if (stableHeartbeat && Recoverable(error) && !cancellation.IsCancellationRequested &&
                !_lifetime.IsCancellationRequested && CanRetainHeartbeat(input, saved.Revision, sentVisibility))
            {
                // No lease renewal is fabricated: the server's existing timeout
                // still expires a sustained outage. Next tick rebuilds live data.
                _recovery = null;
                _withdrawOnly = false;
                Set(acknowledged with { State = "reconnecting", ErrorCode = StableError(error) });
                return;
            }
            // Clear first after an uncertain update. Transport outages retain only
            // the already authorized session; permission/protocol failures do not.
            if (Same(input, _current()))
            {
                _recovery = canResume && !cancellation.IsCancellationRequested && !_lifetime.IsCancellationRequested &&
                    Recoverable(error) ? input : null;
                if (_recovery is null)
                {
                    _restoreBlocked = true;
                    // Invalid authority/contract cannot be bypassed by restarting.
                    // A damaged store also fails closed on the next read.
                    if (!Recoverable(error))
                    {
                        try { _store.SetPublicationConsent(input.Owner, saved.Revision, false, () => Same(input, _current())); }
                        catch (LocalPrivacyException) { }
                    }
                }
                _withdrawOnly = true;
                await WithdrawAsync(input, cancellation).ConfigureAwait(false);
                if (_recovery is not null || Status.State == "withdrawn")
                    Set(new("failed", ErrorCode: StableError(error)));
            }
            else { _active = null; Set(new("inactive")); }
        }
    }

    private bool CanRetainHeartbeat(PrivacyPublicationInput input, long revision, PlayerPresenceVisibilityMode visibility)
    {
        try {
            var current = _current();
            var saved = _store.Read(input.Owner);
            return !_disposed && Same(input, current) && current!.IdentityConfirmed &&
                _visibility() == visibility && saved.Revision == revision &&
                saved.Settings?.PublicationEnabled == true && _store.HasPublicationConsent(input.Owner);
        }
        catch { return false; }
    }


    // Serialize visibility changes with the existing sender. Retain only this
    // session's previous explicit consent, never infer it from a stored policy.
    internal async Task<bool> ChangeVisibilityAsync(BridgeAccountContext owner, long generation,
        Func<CancellationToken, Task> change, CancellationToken cancellation)
    {
        await _gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            var input = _current();
            if (_disposed || input is null || input.Owner != owner || input.Generation != generation)
                throw new LocalPrivacyException("presence.account_changed");
            // A retry-only clear is an obligation, never publication consent.
            var resume = (!_withdrawOnly ? _active : null) ?? _visibilitySuspended ?? _recovery;
            ResetRetry();
            _recovery = null;
            _visibilitySuspended = Same(input, resume) ? resume : null;
            // New positive sends cannot run while authority/storage is changing.
            _withdrawOnly = true;
            try { await change(cancellation).ConfigureAwait(false); }
            catch
            {
                if (Same(input, _current())) { _active = input; await WithdrawAsync(input, cancellation).ConfigureAwait(false); }
                throw;
            }
            if (!Same(input, _current())) throw new LocalPrivacyException("presence.account_changed");
            var visibility = _visibility();
            if (visibility is not (PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame))
            {
                _restoreBlocked = true;
                _visibilitySuspended = Same(input, resume) ? resume : null;
                _active = input;
                return await WithdrawAsync(input, cancellation).ConfigureAwait(false);
            }
            _visibilitySuspended = null;
            _withdrawOnly = false;
            _restoreBlocked = false;
            if (resume is not null && Same(input, resume) || _store.HasPublicationConsent(owner))
            {
                _active = input;
                await SendCurrentAsync(input, _store.Read(owner), cancellation).ConfigureAwait(false);
                return Status.State is "applied" or "withdrawn";
            }
            _active = null;
            Set(new("inactive"));
            return true;
        }
        finally { ReleaseGate(); }
    }

    internal async Task<bool> StopAsync(CancellationToken cancellation, bool explicitRequest = false)
    {
        await _gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            _visibilitySuspended = null;
            _recovery = null;
            _restoreBlocked = true;
            ResetRetry();
            var active = _active ?? (explicitRequest ? _current() : null);
            if (active is null) return true;
            _active = active;
            // Retain only a clear obligation after failure, never publishing consent.
            _withdrawOnly = true;
            if (!Same(active, _current())) { Set(new("inactive")); return false; }
            if (explicitRequest)
            {
                try { _store.SetPublicationConsent(active.Owner, _store.Read(active.Owner).Revision, false, () => Same(active, _current())); }
                catch (LocalPrivacyException error)
                {
                    await WithdrawAsync(active, cancellation).ConfigureAwait(false);
                    Set(new("failed", ErrorCode: error.Code));
                    return false;
                }
            }
            return await WithdrawAsync(active, cancellation).ConfigureAwait(false);
        }
        finally { ReleaseGate(); }
    }

    private async Task<bool> WithdrawAsync(PrivacyPublicationInput active, CancellationToken cancellation)
    {
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            deadline.CancelAfter(TimeSpan.FromSeconds(8));
            await _send(active, PrivacyPublicationPayload.Build(active, LocalPrivacySettings.EditorDefaults, true),
                deadline.Token).ConfigureAwait(false);
            _active = null;
            Set(Same(active, _current()) ? new("withdrawn", AppliedAt: DateTimeOffset.UtcNow) : new("inactive"));
            return true;
        }
        catch (Exception error)
        {
            Set(Same(active, _current()) ? new("withdrawalPending", ErrorCode: StableError(error)) : new("inactive"));
            return false;
        }
    }

    private PrivacyPublicationStatus Set(PrivacyPublicationStatus status)
    {
        if (_recovery is not null && status.State is "withdrawn" or "withdrawalPending" or "failed")
            status = status with { State = "reconnecting" };
        var previous = Status;
        Volatile.Write(ref _status, status);
        if (previous.State != status.State || previous.ErrorCode != status.ErrorCode)
            try { Diagnostic?.Invoke(status.State, status.ErrorCode); } catch { /* Evidence cannot change sharing. */ }
        return status;
    }
    private static bool Recoverable(Exception error) => error is HttpRequestException { StatusCode: null } or
        // SemaphoreSlim and cancellationToken.ThrowIfCancellationRequested use
        // the base type, unlike HttpClient's TaskCanceledException. The callers
        // separately exclude user/lifetime cancellation before resuming consent.
        OperationCanceledException or Account.AccountBridgeHostException { Code: "privacy_publication.temporarily_unavailable" };
    private static string StableError(Exception error) => error switch {
        LocalPrivacyException e => e.Code,
        Account.AccountBridgeHostException { HttpStatus: System.Net.HttpStatusCode.RequestTimeout } => "privacy_publication.timeout",
        Account.AccountBridgeHostException { HttpStatus: System.Net.HttpStatusCode.TooManyRequests } => "privacy_publication.rate_limited",
        Account.AccountBridgeHostException { HttpStatus: { } status } when (int)status >= 500 => "privacy_publication.server_error",
        Account.AccountBridgeHostException e => e.Code,
        HttpRequestException { StatusCode: null } => "privacy_publication.network_unavailable",
        OperationCanceledException => "privacy_publication.timeout",
        _ => "privacy_publication.unavailable"
    };
    private void ResetRetry() { _retryFailures = 0; _retryAfter = default; _retryRevision = null; }
    private void ScheduleRetry(long revision)
    {
        _retryRevision = revision;
        var seconds = Math.Min(60, 5 * (1 << Math.Min(_retryFailures++, 4)));
        _retryAfter = _clock.GetUtcNow().AddSeconds(seconds);
    }
    public void Dispose() { _disposed = true; _timer?.Dispose(); _lifetime.Cancel(); _active = null; _recovery = null; }
}
