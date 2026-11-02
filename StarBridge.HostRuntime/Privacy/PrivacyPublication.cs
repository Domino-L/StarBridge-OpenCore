using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

/// <summary>Real-time fields only. Inventory and event feeds keep their own consent/contracts.</summary>
internal sealed record PrivacyPublicationInput(BridgeAccountContext Owner, long Generation,
    string Handle, bool IdentityConfirmed, string? GameVersion, GameLogSessionSnapshot Game,
    bool AppAway = false, bool PrioritizeNetwork = false, bool AppPresenceConfirmed = false,
    Action? RequirePositiveAdmission = null, PositivePublicationAdmission? PositiveAdmission = null);

internal sealed record PrivacyPublicationStatus(string State, long? AppliedRevision = null,
    DateTimeOffset? AppliedAt = null, string? ErrorCode = null, bool? FirstUseRequired = null)
{
    public int SchemaVersion => 1;
    public int SupportedFields => (int)PlayerSharedStateAudiencePolicy.PartyRoomLiveStateFields;
}

internal static partial class PrivacyPublicationPayload
{
    internal static JsonElement Build(PrivacyPublicationInput input, LocalPrivacySettings settings, bool clear, PlayerPresenceVisibilityMode visibility = PlayerPresenceVisibilityMode.Online)
    {
        var enabled = settings.PublicationEnabled && !clear &&
            visibility is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame;
        const PlayerSharedStateFields supported = PlayerSharedStateAudiencePolicy.PartyRoomLiveStateFields;
        var legacyEnabled = enabled && input.IdentityConfirmed;
        var fleet = legacyEnabled && settings.Communities is null ? settings.Fleet.Fields & supported : PlayerSharedStateFields.None;
        var room = legacyEnabled ? settings.Room.Fields & supported : PlayerSharedStateFields.None;
        // Do not upload fields without any potential audience. Remote authorization
        // remains authoritative; a local group ID never grants membership.
        var effectiveFleet = settings.Fleet.AllMembersCanView || settings.Fleet.AdministratorsCanView
            ? fleet : PlayerSharedStateFields.None;
        var effectiveRoom = settings.Room.AllMembersCanView ? room : PlayerSharedStateFields.None;
        var communities = settings.Communities is null ? null : legacyEnabled
            ? CommunityRealtimeScope.ValidateAndCopy(settings.Communities) : [];
        var fields = effectiveFleet | effectiveRoom;
        if (enabled && settings.OfficialFleet is { } official && (input.AppPresenceConfirmed || input.IdentityConfirmed && input.GameVersion is not null)) fields |= official.Fields;
        foreach (var scope in communities ?? [])
            fields |= scope.PotentialFields;
        bool Has(PlayerSharedStateFields field) => fields.HasFlag(field);
        var playing = enabled && input.IdentityConfirmed && input.GameVersion is not null;
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
        if (communities is null) return AddOfficial(payload, input, settings.OfficialFleet, enabled, playing);
        var body = System.Text.Json.Nodes.JsonNode.Parse(payload.GetRawText())!.AsObject();
        body["communities"] = JsonSerializer.SerializeToNode(communities, LocalPrivacyStore.Json);
        return AddOfficial(JsonSerializer.SerializeToElement(body), input, settings.OfficialFleet, enabled, playing);
    }
}

/// <summary>
/// Account-scoped explicit consent + serialized latest-snapshot publication.
/// Saving local choices alone cannot activate sharing. No persisted payload queue.
/// </summary>
internal sealed partial class PrivacyPublication : IDisposable
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
    private readonly PrivacyPublicationLane _lane;
    private readonly Func<Settings.PublicationVisibilitySnapshot> _visibilitySnapshot;
    private readonly Action<BridgeAccountContext, long>? _confirmExplicitSharing;
    private readonly Func<BridgeAccountContext, long, bool>? _consumeExplicitOnlineResume;
    private readonly Func<PrivacyPublicationInput?> _current;
    private readonly Func<PrivacyPublicationInput?> _currentOwner;
    private readonly Func<BridgeAccountContext, long, bool>? _roomPublicationActive;
    private readonly Func<PrivacyPublicationInput, JsonElement, CancellationToken, Task> _send;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private readonly Lifecycle.DeferredWorkTimer _timer;
    private readonly TimeProvider _clock;
    private int _retryFailures;
    private int _longRetryFailures;
    private DateTimeOffset _retryAfter;
    private long? _retryRevision;
    private PrivacyPublicationInput? _active;
    private PrivacyPublicationInput? _wireContractOwner;
    private bool _scopedWireContract;
    private bool _withdrawOnly;
    private StarBridge.Core.Presence.OfficialFleetRealtimeChoice? _officialWireContract;
    private PrivacyPublicationInput? _visibilitySuspended;
    // Recoverable failures retain a retry intent; consent is only user-owned.
    // This is not a payload queue: every retry rebuilds current fields/policy.
    private PrivacyPublicationInput? _recovery;
    private bool _restoreBlocked;
    private string? _publicationFailure;
    private bool _manualPause;
    private int _unauthorizedFailures;
    private PrivacyPublicationStatus _status = new("inactive");
    private volatile bool _disposed;
    private int _tickPending;
    private PrivacyPublicationInput? _pendingClear;
    private int _clearRetryFailures;
    private DateTimeOffset _clearRetryAfter;
    private PrivacyPublicationInput? _pendingPause;
    private string? _retryError;
    internal bool ClearPending => _pendingClear is not null;
    internal TimeSpan VisibilityTimeout { get; init; } = TimeSpan.FromSeconds(20);

    internal PrivacyPublication(LocalPrivacyStore store, Func<PrivacyPublicationInput?> current,
        Func<PrivacyPublicationInput, JsonElement, CancellationToken, Task> send, bool startTimer = true,
        Func<PlayerPresenceVisibilityMode>? visibility = null, TimeProvider? timeProvider = null,
        Action<BridgeAccountContext, long>? confirmExplicitSharing = null,
        Func<Settings.PublicationVisibilitySnapshot>? visibilitySnapshot = null,
        Func<BridgeAccountContext, long, bool>? consumeExplicitOnlineResume = null,
        Func<PrivacyPublicationInput?>? currentOwner = null,
        Func<BridgeAccountContext, long, bool>? roomPublicationActive = null, PrivacyPublicationLane lane = PrivacyPublicationLane.Combined)
    {
        _store = store; _current = current; _send = send; _lane = lane;
        _currentOwner = currentOwner ?? current;
        _roomPublicationActive = roomPublicationActive;
        _visibilitySnapshot = visibilitySnapshot ?? (() => {
            var input = current();
            return new(input?.Owner, input?.Generation ?? 0, "", null,
                visibility?.Invoke() ?? PlayerPresenceVisibilityMode.Online, null);
        });
        _confirmExplicitSharing = confirmExplicitSharing;
        _consumeExplicitOnlineResume = consumeExplicitOnlineResume;
        _clock = timeProvider ?? TimeProvider.System;
        _timer = new(_clock, PeriodicTickAsync,
            TimeSpan.FromSeconds(5), Timeout.InfiniteTimeSpan);
        if (startTimer) _timer.Start();
    }
    internal bool StartDeferredWork() => !_disposed && _timer.Start();
    internal PrivacyPublicationStatus Status => Volatile.Read(ref _status);
    internal Action<string, string?>? Diagnostic { get; set; }
    /// Raised after the observable state or error changes, so the client can
    /// re-read on demand instead of polling the status every five seconds.
    internal event Action? StatusChanged;
    internal void Invalidate()
    {
        _unauthorizedFailures = 0;
        _publicationFailure = null;
        _manualPause = false;
        _active = null;
        _visibilitySuspended = null;
        _recovery = null;
        _restoreBlocked = false;
        _pendingClear = null;
        ResetClearRetry();
        _withdrawOnly = true;
        ResetRetry();
        Set(new("inactive"));
    }
    private bool Same(PrivacyPublicationInput a, PrivacyPublicationInput? b) =>
        b is not null && a.Owner == b.Owner && a.Generation == b.Generation && a.Handle == b.Handle;

    internal async Task<PrivacyPublicationStatus> ApplyAsync(BridgeAccountContext owner, long generation,
        long revision, CancellationToken cancellation, bool preservePause = false)
    {
        using var work = _work.Enter(cancellation);
        if (work is null || _disposed) throw new LocalPrivacyException("privacy_publication.account_changed");
        cancellation = work.Token;
        await _gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            var observationVersion = ObservationVersion();
            var input = _current() ?? _currentOwner();
            if (_disposed || input is null || input.Owner != owner || input.Generation != generation)
                throw new LocalPrivacyException("privacy_publication.account_changed");
            var saved = _store.Read(owner);
            if (saved.Settings is null || saved.Revision != revision)
                throw new LocalPrivacyException("privacy_publication.refresh_required");
            // An audience choice is not an instruction to resume paused sharing
            // or change visibility. Check under the existing publication gate.
            if (preservePause)
            {
                var choiceVisibility = ReadVisibility(input);
                await PersistObservedPauseAsync(input, cancellation).ConfigureAwait(false);
                if (choiceVisibility.Mode is not (PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame))
                    return Set(new("withdrawn", AppliedRevision: revision));
            }
            if (preservePause && (_manualPause || _store.IsPublicationPaused(owner) || _store.IsPublicationRevoked(owner) ||
                HasObservedPause(input)))
                return Set(new("withdrawn", AppliedRevision: revision));
            // A choice showing only the official four cannot grant global
            // consent for old ordinary audiences that were never applied.
            if (preservePause && !_store.HasPublicationConsent(owner) &&
                (saved.Settings.Fleet.Fields != PlayerSharedStateFields.None ||
                 saved.Settings.Room.Fields != PlayerSharedStateFields.None ||
                 saved.Settings.Communities is { Length: > 0 } || saved.Settings.Events is not null))
                return Set(new("inactive", ErrorCode: "privacy_publication.existing_scope_confirmation_required"));
            await _store.SetPublicationConsentAsync(owner, revision, saved.Settings.PublicationEnabled,
                () => !_disposed && Same(input, _currentOwner()), cancellation).ConfigureAwait(false);
            if (!preservePause) ResetObservedPause(observationVersion); // Retain newer observations.
            _recovery = null;
            _publicationFailure = null;
            _unauthorizedFailures = 0;
            _restoreBlocked = false;
            ResetRetry();
            // Official app-only consent uses the authenticated heartbeat; game
            // identity remains required for every original audience and game field.
            if (!LaneConfigured(input, saved.Settings)) { await DeactivateLaneAsync(cancellation).ConfigureAwait(false); return Status; }
            if (!HasObservedPause(input) && !HasPublicationEvidence(input, saved.Settings) && saved.Settings.PublicationEnabled)
                return Set(new("identityRequired"));
            cancellation.ThrowIfCancellationRequested();
            if (saved.Settings.PublicationEnabled && !preservePause) _confirmExplicitSharing?.Invoke(owner, generation);
            _active = input;
            _withdrawOnly = false;
            await SendCurrentAsync(input, saved, cancellation).ConfigureAwait(false);
            return Status;
        }
        finally { ReleaseGate(); }
    }

    private async Task PeriodicTickAsync()
    {
        using var work = _work.Enter(default);
        if (work is null || _disposed) return;
        // Elapsed timer intervals carry no new evidence. Do not enqueue a
        // trailing publication behind a slow request; leave room for reads.
        if (!await _gate.WaitAsync(0).ConfigureAwait(false)) { RearmTimer(); return; }
        try { if (!_disposed) await TickCoreAsync().ConfigureAwait(false); }
        finally { ReleaseGate(); }
    }

    private void RearmTimer()
    {
        if (_disposed) return;
        try { _timer?.Change(TimeSpan.FromSeconds(5), Timeout.InfiniteTimeSpan); }
        catch (ObjectDisposedException) { /* Shutdown won the race. */ }
    }

    internal async Task TickAsync()
    {
        using var work = _work.Enter(default);
        if (work is null || _disposed) return;
        Interlocked.Exchange(ref _tickPending, 1);
        if (!await _gate.WaitAsync(0).ConfigureAwait(false)) return;
        try
        {
            if (_disposed) return;
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
        RearmTimer();
        _gate.Release();
        // Explicit apply/visibility changes must also drain pending input wakes.
        // Every pass rechecks current ownership, consent and game evidence.
        if (!_disposed && Volatile.Read(ref _tickPending) != 0) _ = TickAsync();
    }

    private async Task TickCoreAsync()
    {
        if (_disposed) return;
        try
        {
            var observed = _current() ?? _currentOwner();
            if (observed is not null && !LaneConfigured(observed, _store.Read(observed.Owner).Settings)) { await DeactivateLaneAsync(_lifetime.Token).ConfigureAwait(false); return; }
            var hasConsent = observed is not null && _store.HasPublicationConsent(observed.Owner) &&
                _store.Read(observed.Owner).Settings?.PublicationEnabled == true;
            if (hasConsent) _confirmExplicitSharing?.Invoke(observed!.Owner, observed.Generation);
            var visibility = ReadVisibility(observed);
            // Definite invisibility must be durable even when a provisional
            // suspension has already cleared _active and blocked restoration.
            if (observed is not null && HasObservedPause(observed))
            {
                await PersistObservedPauseAsync(observed, _lifetime.Token).ConfigureAwait(false);
                // Room renewal has its own authority. Persist its pause without
                // inventing a telemetry withdrawal for an unconsented account.
                if (hasConsent || _active is not null || _pendingClear is not null)
                {
                    _withdrawOnly = true;
                    if (_active is null && Status.AppliedAt is null)
                    {
                        // A cold publisher still owes one clear of possible remote
                        // state; persisting pause cannot erase that obligation.
                        _active = observed;
                    }
                    else if (_active is null) Set(Status with { State = "withdrawn", ErrorCode = null });
                }
            }
            var active = _active;
            // A startup/disconnection clear is not a manual stop. Resume only
            // this account's remembered consent after current server evidence.
            if (active is null && _visibilitySuspended is { } suspended &&
                Same(suspended, _current()) && _store.HasPublicationConsent(suspended.Owner) &&
                !_store.IsPublicationPaused(suspended.Owner))
            {
                if (visibility.Mode is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame)
                {
                    _visibilitySuspended = null;
                    _restoreBlocked = false;
                }
            }
            if (active is null && _recovery is { } recovery)
            {
                active = _active = recovery;
                _recovery = null;
                _withdrawOnly = false;
            }
            // Owner-only fallback may process a suspension/clear, never positive
            // publication. App-only sessions lose positive input on null/0.
            var suspensionOwner = visibility.Mode is not (PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame)
                ? _currentOwner() : null;
            if (active is null && !_restoreBlocked && (_current() ?? suspensionOwner) is { } candidate &&
                _store.HasPublicationConsent(candidate.Owner))
            {
                if (!HasPublicationEvidence(candidate, _store.Read(candidate.Owner).Settings) && visibility.Mode is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame)
                { Set(new("identityRequired")); return; }
                active = _active = candidate;
                _withdrawOnly = false;
            }
            if (active is null) return;
            var input = _current() ?? (_withdrawOnly || HasObservedPause(active) ? _currentOwner() : suspensionOwner);
            if (!Same(active, input)) { _active = null; Set(new("inactive")); return; }
            if (_withdrawOnly) await WithdrawAsync(active, _lifetime.Token).ConfigureAwait(false);
            else await SendCurrentAsync(input!, _store.Read(active.Owner), _lifetime.Token, background: true, snapshot: visibility).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            if (_disposed) return;
            if (Recoverable(error) && _current() is { } retry && !HasObservedPause(retry) && _store.HasPublicationConsent(retry.Owner))
            {
                _recovery = retry;
                ScheduleRetry(_store.Read(retry.Owner).Revision, error);
                Set(new("reconnecting", ErrorCode: StableError(error)));
                return;
            }
            // A corrupt/unreadable policy cannot keep the old published fields live.
            _recovery = null;
            // Owner verification can recover without a new login generation.
            // Do not treat that temporary gate as a damaged local policy, but
            // never clear a prior explicit stop or a hard restoration block.
            _restoreBlocked |= error is not LocalPrivacyReadUnavailableException;
            _withdrawOnly = true;
            _publicationFailure = StableError(error);
            if (_active is { } active && Same(active, _currentOwner()))
                await WithdrawAsync(active, _lifetime.Token).ConfigureAwait(false);
            if (Status.State != "withdrawalPending") Set(new("failed", ErrorCode: StableError(error)));
        }
    }

    private async Task SendCurrentAsync(PrivacyPublicationInput input, LocalPrivacySnapshot saved, CancellationToken cancellation,
        bool background = false, Settings.PublicationVisibilitySnapshot? snapshot = null)
    {
        var canResume = false;
        var acknowledged = Status;
        var stableHeartbeat = false;
        var sendingClear = false;
        var sentVisibility = PlayerPresenceVisibilityMode.Online;
        try
        {
            var settings = saved.Settings ?? throw new LocalPrivacyException("privacy_publication.refresh_required");
            if (!LaneConfigured(input, settings)) { await DeactivateLaneAsync(cancellation).ConfigureAwait(false); return; }
            _wireContractOwner = input;
            _scopedWireContract = settings.Communities is not null;
            _officialWireContract = settings.OfficialFleet;
            var consent = _store.HasPublicationConsent(input.Owner);
            snapshot ??= ReadVisibility(input);
            ObserveVisibility(snapshot);
            await PersistObservedPauseAsync(input, cancellation).ConfigureAwait(false);
            var visibility = snapshot.Mode;
            var invisible = visibility is not (PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame);
            var visibilityError = invisible ? snapshot.SuspensionError : null;
            if (visibilityError == "privacy_local.read_unavailable") throw new LocalPrivacyReadUnavailableException();
            if (visibilityError is "privacy_local.read_failed" or "privacy_local.write_failed")
                throw new LocalPrivacyException(visibilityError);
            if (_store.IsPublicationPaused(input.Owner))
            { invisible = true; visibility = PlayerPresenceVisibilityMode.Invisible; visibilityError = null; }
            sentVisibility = visibility;
            _manualPause = _store.IsPublicationRevoked(input.Owner) || !settings.PublicationEnabled || invisible && visibilityError is null;
            if (!consent && !_manualPause && acknowledged.AppliedAt is null)
            { _active = null; Set(new("inactive")); return; }
            if (_manualPause) _publicationFailure = null;
            var clear = !consent || !settings.PublicationEnabled ||
                !HasPublicationEvidence(input, settings) || invisible;
            sendingClear = clear;
            if (clear && ClearRetryDeferred(input)) return;
            // Input wakes cannot bypass transport backoff. Authority is checked
            // first; the initial privacy clear is immediate, failed clears use
            // their independent deadline above.
            if (background && !clear && _retryRevision == saved.Revision && _clock.GetUtcNow() < _retryAfter) return;
            canResume = consent && settings.PublicationEnabled && (!invisible || visibilityError is not null);
            if (canResume && invisible) _visibilitySuspended = input;
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
            void RequirePositiveAdmission()
            {
                if (!CanRetainHeartbeat(input, saved.Revision, visibility, out var admissionVisibility))
                    throw new PositivePublicationSupersededException(admissionVisibility);
            }
            await _send(input with { PrioritizeNetwork = !background || clear,
                    RequirePositiveAdmission = clear ? null : RequirePositiveAdmission,
                    PositiveAdmission = clear ? null : _store.PositiveAdmission },
                BuildPayload(input, settings, clear, visibility), deadline.Token).ConfigureAwait(false);
            if (_disposed || !Same(input, _currentOwner())) { _active = null; Set(new("inactive")); return; }
            if (_store.Read(input.Owner).Revision != saved.Revision)
            { Set(new("pending")); return; }
            _publicationFailure = null;
            _unauthorizedFailures = 0;
            if (clear) { _pendingClear = null; ResetClearRetry(); }
            ResetRetry();
            var state = !clear ? "applied" : _manualPause ? "withdrawn" : visibilityError switch {
                "privacy_publication.network_unavailable" => "reconnecting",
                null or "privacy_publication.identity_pending" => "identityRequired",
                _ => "failed"
            };
            Set(new(state, saved.Revision, _clock.GetUtcNow(), _manualPause ? null : visibilityError));
            // Successful invisible clear stops even empty periodic snapshots.
            if (invisible || !consent || !settings.PublicationEnabled)
            {
                _visibilitySuspended = invisible && canResume ? input : null;
                _active = null;
                _restoreBlocked = true;
            }
        }
        catch (PositivePublicationSupersededException rejected)
        {
            if (_disposed || !Same(input, _currentOwner())) { _active = null; Set(new("inactive")); return; }
            // Re-read policy, but retain the exact visibility that denied the
            // send. A later provisional/online observation cannot erase it.
            var latest = _store.Read(input.Owner);
            var consent = _store.HasPublicationConsent(input.Owner);
            var latestVisibility = rejected.Visibility;
            if (latestVisibility is not null) ObserveVisibility(latestVisibility);
            await PersistObservedPauseAsync(input, cancellation).ConfigureAwait(false);
            _manualPause = _store.IsPublicationRevoked(input.Owner) || latest.Settings?.PublicationEnabled != true ||
                _store.IsPublicationPaused(input.Owner);
            _publicationFailure = null;
            _restoreBlocked = _manualPause;
            _recovery = consent && !_manualPause ? input : null;
            _withdrawOnly = true;
            ResetRetry();
            await WithdrawAsync(input, cancellation).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            if (_disposed) return;
            var identityRequired = RequiresIdentity(error);
            if (Recoverable(error)) ScheduleRetry(saved.Revision, error);
            var retainHeartbeat = false;
            if (stableHeartbeat && !identityRequired && ShortRetry(error) && !_lifetime.IsCancellationRequested)
            {
                retainHeartbeat = CanRetainHeartbeat(input, saved.Revision, sentVisibility, out var failureVisibility);
                if (failureVisibility is not null) ObserveVisibility(failureVisibility);
            }
            // The writer has released admission. Persist the exact observation,
            // never sample again; a failed write keeps the latched obligation.
            try { await PersistObservedPauseAsync(input, cancellation).ConfigureAwait(false); }
            catch (Exception pauseError) { error = pauseError; retainHeartbeat = false; }
            if (retainHeartbeat)
            {
                // No lease renewal is fabricated: the server's existing timeout
                // still expires a sustained outage. Next tick rebuilds live data.
                _recovery = null;
                _withdrawOnly = false;
                Set(acknowledged with { State = "reconnecting", ErrorCode = StableError(error) });
                return;
            }
            // Clear first after an uncertain update. Every non-auth retry keeps
            // the already authorized session, with its own error and backoff.
            if (Same(input, _currentOwner()))
            {
                if (sendingClear) ScheduleClearRetry(input);
                _recovery = canResume && !HasObservedPause(input) && !identityRequired && !_lifetime.IsCancellationRequested &&
                    Recoverable(error) ? input : null;
                if (_recovery is null)
                {
                    _visibilitySuspended = null;
                    _restoreBlocked |= error is not LocalPrivacyReadUnavailableException;
                    // Fail closed for this session, without revoking the user's
                    // choice. A new ready account/startup may validate it again.
                    _publicationFailure = _manualPause ? null : StableError(error);
                }
                _withdrawOnly = true;
                if (sendingClear)
                    Set(new(identityRequired ? "identityRequired" : "withdrawalPending", ErrorCode: StableError(error)));
                await WithdrawAsync(input, cancellation).ConfigureAwait(false);
                if (_recovery is not null || _publicationFailure is not null)
                    Set(new("failed", ErrorCode: StableError(error)));
            }
            else
            {
                _active = null;
                // Existing OAuth invalidation may retire the session before the
                // send unwinds. Retain only the reason, never its old payload.
                Set(identityRequired && _current() is null
                    ? new("identityRequired", ErrorCode: "privacy_publication.identity_unavailable")
                    : new("inactive"));
            }
        }
    }

    private async Task DeactivateLaneAsync(CancellationToken cancellation)
    {
        // A removed audience still owes a clear using its previous wire contract.
        // Failed clears retain their normal retry obligation instead of becoming inactive.
        _recovery = null;
        _visibilitySuspended = null;
        var prior = _pendingClear ?? _active;
        if (prior is not null) await WithdrawAsync(prior, cancellation).ConfigureAwait(false);
        else Set(new("inactive"));
    }
    private bool LaneConfigured(PrivacyPublicationInput input, LocalPrivacySettings? settings) => _lane switch {
        PrivacyPublicationLane.Official => settings?.OfficialFleet is not null,
        // A new SCM-only account has no legacy handle or ordinary scope to
        // withdraw. Never send a fabricated empty identity to the old route.
        PrivacyPublicationLane.Ordinary when input.Handle.Length == 0 && settings?.OfficialFleet is not null =>
            settings.Fleet.Fields != 0 || settings.Room.Fields != 0 || settings.Communities is { Length: > 0 },
        _ => true
    };
    private JsonElement BuildPayload(PrivacyPublicationInput input, LocalPrivacySettings settings, bool clear,
        PlayerPresenceVisibilityMode visibility = PlayerPresenceVisibilityMode.Online)
    {
        settings = _lane switch {
            PrivacyPublicationLane.Ordinary => settings with { OfficialFleet = null },
            PrivacyPublicationLane.Official => settings with { Fleet = new(0, false, false, []),
                Room = new(0, false), Communities = [], Events = null },
            _ => settings
        };
        return PrivacyPublicationPayload.Build(input, settings, clear, visibility);
    }
    private bool HasPublicationEvidence(PrivacyPublicationInput input, LocalPrivacySettings? settings) =>
        input.IdentityConfirmed || _lane != PrivacyPublicationLane.Ordinary && settings?.OfficialFleet is { } official &&
        (official.Fields == PlayerSharedStateFields.None || input.AppPresenceConfirmed);

    private sealed class PositivePublicationSupersededException(Settings.PublicationVisibilitySnapshot? visibility)
        : OperationCanceledException
    {
        internal Settings.PublicationVisibilitySnapshot? Visibility { get; } = visibility;
    }

    private Settings.PublicationVisibilitySnapshot ReadVisibility(PrivacyPublicationInput? input)
    {
        var snapshot = _visibilitySnapshot();
        ObserveVisibility(snapshot);
        return input is not null && snapshot.Owner == input.Owner && snapshot.Generation == input.Generation
            ? snapshot : snapshot with { Mode = PlayerPresenceVisibilityMode.Invisible,
                SuspensionError = "privacy_publication.account_changed" };
    }

    private bool CanRetainHeartbeat(PrivacyPublicationInput input, long revision, PlayerPresenceVisibilityMode visibility,
        out Settings.PublicationVisibilitySnapshot? snapshot)
    {
        snapshot = null;
        try {
            var current = _current();
            var saved = _store.Read(input.Owner);
            snapshot = ReadVisibility(input);
            return !_disposed && Same(input, current) && HasPublicationEvidence(current!, saved.Settings) &&
                snapshot.Mode == visibility && saved.Revision == revision &&
                IsPositivePublicationAllowed(input, snapshot);
        }
        catch { return false; }
    }


    // Serialize visibility changes with the existing sender. Retain only this
    // session's previous explicit consent, never infer it from a stored policy.
    internal Task<bool> ChangeVisibilityAsync(BridgeAccountContext owner, long generation,
        Func<CancellationToken, Task> change, CancellationToken cancellation) =>
        ChangeVisibilityCoreAsync(owner, generation, change, cancellation, false);
    internal Task<bool> PrepareVisibilityAsync(BridgeAccountContext owner, long generation,
        Func<CancellationToken, Task> change, CancellationToken cancellation) =>
        ChangeVisibilityCoreAsync(owner, generation, change, cancellation, true);
    private async Task<bool> ChangeVisibilityCoreAsync(BridgeAccountContext owner, long generation,
        Func<CancellationToken, Task> change, CancellationToken cancellation, bool deferPositive)
    {
        using var work = _work.Enter(cancellation);
        if (work is null || _disposed) throw new LocalPrivacyException("presence.account_changed");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
        deadline.CancelAfter(VisibilityTimeout);
        cancellation = deadline.Token;
        await _gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            var input = _current() ?? _currentOwner();
            if (_disposed || input is null || input.Owner != owner || input.Generation != generation)
                throw new LocalPrivacyException("presence.account_changed");
            // A retry-only clear is an obligation, never publication consent.
            var resume = (!_withdrawOnly ? _active : null) ?? _visibilitySuspended ?? _recovery;
            _publicationFailure = null;
            ResetRetry();
            _recovery = null;
            _visibilitySuspended = Same(input, resume) ? resume : null;
            // New positive sends cannot run while authority/storage is changing.
            _withdrawOnly = true;
            try
            {
                // _gate is already held. Release admission before any metadata
                // method (which takes its own lease), clear, or follow-up send.
                using var admission = await _store.PositiveAdmission.EnterAsync(cancellation).ConfigureAwait(false);
                await change(cancellation).WaitAsync(cancellation).ConfigureAwait(false);
            }
            catch (Exception error)
            {
                if (!_disposed && Same(input, _currentOwner()))
                {
                    _active = input;
                    if (Recoverable(error) && _store.HasPublicationConsent(owner))
                    {
                        _recovery = input;
                        _restoreBlocked = false;
                        ScheduleRetry(_store.Read(owner).Revision, error);
                    }
                    await WithdrawAsync(input, cancellation).ConfigureAwait(false);
                }
                throw;
            }
            if (!work.IsCurrent || _disposed || !Same(input, _currentOwner())) throw new LocalPrivacyException("presence.account_changed");
            var observationVersion = ObservationVersion();
            var snapshot = ReadVisibility(input);
            var visibility = snapshot.Mode;
            var explicitlyResumed = _consumeExplicitOnlineResume?.Invoke(owner, generation) == true;
            if (explicitlyResumed || visibility is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame)
            {
                await _store.SetPublicationPausedAsync(owner, _store.Read(owner).Revision, false, () => Same(input, _currentOwner()), cancellation).ConfigureAwait(false);
                ResetObservedPause(observationVersion);
            }
            await PersistObservedPauseAsync(input, cancellation).ConfigureAwait(false);
            if (!_store.HasPublicationConsent(owner) && resume is null && _active is null)
            { Set(new("inactive")); return true; }
            if (visibility is not (PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame))
            {
                if (snapshot.SuspensionError is not null)
                {
                    _active = input;
                    _withdrawOnly = false;
                    await SendCurrentAsync(input, _store.Read(owner), cancellation, snapshot: snapshot).ConfigureAwait(false);
                    return Status.AppliedAt is not null;
                }
                _manualPause = true;
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
                if (deferPositive) return true;
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
        using var work = _work.Enter(cancellation);
        if (work is null || _disposed) return false;
        cancellation = work.Token;
        await _gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            // Same order as writer: _gate then admission, never the reverse.
            // No positive work can start after this stop commits under _gate.
            using (await _store.PositiveAdmission.EnterAsync(cancellation).ConfigureAwait(false))
                _withdrawOnly = true;
            _visibilitySuspended = null;
            _publicationFailure = null;
            _manualPause = explicitRequest;
            _recovery = null;
            _restoreBlocked = true;
            ResetRetry();
            var withdrawalRequired = _active is not null || _pendingClear is not null;
            var active = explicitRequest ? _currentOwner() : _active;
            if (active is null) return true;
            _active = active;
            // Retain only a clear obligation after failure, never publishing consent.
            _withdrawOnly = true;
            if (!Same(active, _currentOwner())) { Set(new("inactive")); return false; }
            if (explicitRequest)
            {
                try { await _store.SetPublicationConsentAsync(active.Owner, _store.Read(active.Owner).Revision, false,
                    () => Same(active, _currentOwner()), cancellation, withdrawalRequired).ConfigureAwait(false); }
                catch (LocalPrivacyException error)
                {
                    await WithdrawAsync(active, cancellation).ConfigureAwait(false);
                    Set(new("failed", ErrorCode: error.Code));
                    return false;
                }
            }
            // Stop/retirement is an explicit lifecycle boundary, not a passive
            // retry tick. It must attempt its own clear and allow a later user
            // retry immediately after the transport recovers.
            ResetClearRetry();
            var withdrawn = await WithdrawAsync(active, cancellation).ConfigureAwait(false);
            if (explicitRequest && !withdrawn && !withdrawalRequired)
            {
                // A speculative clear for a fresh account creates no record on
                // success. A failed clear now has a real retry obligation.
                try { await _store.SetPublicationConsentAsync(active.Owner, _store.Read(active.Owner).Revision, false,
                    () => Same(active, _currentOwner()), cancellation, withdrawalRequired: true).ConfigureAwait(false); }
                catch (LocalPrivacyException error) { Set(new("failed", ErrorCode: error.Code)); }
            }
            return withdrawn;
        }
        finally { ReleaseGate(); }
    }

    private async Task<bool> WithdrawAsync(PrivacyPublicationInput active, CancellationToken cancellation)
    {
        if (ClearRetryDeferred(active)) return false;
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            deadline.CancelAfter(TimeSpan.FromSeconds(8));
            // Clearing must retain the saved wire contract. EditorDefaults has
            // no community marker and would downgrade an SCM-scoped withdrawal
            // to the legacy-only endpoint. Retain only the protocol bit for the
            // same account/session so corrupted local policy cannot block a
            // compensating clear. No previous audience or payload is retained.
            var settings = LocalPrivacySettings.EditorDefaults;
            if (Same(active, _wireContractOwner))
                settings = settings with { Communities = _scopedWireContract ? [] : null, OfficialFleet = _officialWireContract };
            else
                settings = _store.Read(active.Owner).Settings ?? settings;
            if (LaneConfigured(active, settings))
                await _send(active, BuildPayload(active, settings, true),
                deadline.Token).ConfigureAwait(false);
            _pendingClear = null;
            ResetClearRetry();
            _active = null;
            var state = _recovery is not null ? "reconnecting" : _publicationFailure is not null ? "failed" :
                _manualPause ? "withdrawn" : "inactive";
            Set(Same(active, _currentOwner()) ? new(state, AppliedAt: DateTimeOffset.UtcNow,
                ErrorCode: _publicationFailure ?? (_recovery is not null ? _retryError : null)) : new("inactive"));
            return true;
        }
        catch (Exception error)
        {
            ScheduleClearRetry(active);
            var identityRequired = RequiresIdentity(error);
            if (identityRequired)
            {
                _recovery = null;
                _restoreBlocked = true;
                // A manual withdrawal remains an obligation, not a failed
                // positive publication. Its later success must say withdrawn.
                if (!_manualPause) _publicationFailure = "privacy_publication.identity_unavailable";
            }
            Set(Same(active, _currentOwner()) || identityRequired && _current() is null
                ? new(identityRequired ? "identityRequired" : "withdrawalPending", ErrorCode: StableError(error))
                : new("inactive"));
            return false;
        }
    }

    private bool ClearRetryDeferred(PrivacyPublicationInput input) =>
        _pendingClear is { } pending && Same(input, pending) && _clock.GetUtcNow() < _clearRetryAfter;

    private void ResetClearRetry() { _clearRetryFailures = 0; _clearRetryAfter = default; }

    private void ScheduleClearRetry(PrivacyPublicationInput input)
    {
        if (_pendingClear is null || !Same(input, _pendingClear)) ResetClearRetry();
        _pendingClear = input;
        var minutes = new[] { 1, 5, 15 }[Math.Min(_clearRetryFailures, 2)];
        _clearRetryFailures = Math.Min(_clearRetryFailures + 1, 2);
        _clearRetryAfter = _clock.GetUtcNow().AddMinutes(minutes);
    }

    private bool RequiresIdentity(Exception error)
    {
        if (error is Account.AccountBridgeHostException hard && HardFailure(hard)) return false;
        if (error is Account.AccountBridgeHostException {
            Code: "privacy_publication.identity_unavailable" or Account.AccountBridgeStableErrors.ReauthorizationRequired,
            HttpStatus: null } || error is Auth.ScmApiAuthenticationException) return true;
        return HttpStatus(error) == System.Net.HttpStatusCode.Unauthorized && ++_unauthorizedFailures >= 3;
    }

    private PrivacyPublicationStatus Set(PrivacyPublicationStatus status)
    {
        // Cleanup is not a manual pause, including a later successful clear.
        if (_publicationFailure is not null && status.State is "withdrawn" or "withdrawalPending")
            status = status with { State = "failed", ErrorCode = _publicationFailure };
        if (_recovery is not null && status.State is "withdrawn" or "withdrawalPending" or "failed")
            status = status with { State = "reconnecting" };
        if (_publicationFailure == "privacy_publication.identity_unavailable" &&
            status.State is "failed" or "withdrawalPending")
            status = status with { State = "identityRequired", ErrorCode = _publicationFailure };
        var previous = Status;
        Volatile.Write(ref _status, status);
        if (previous.State != status.State || previous.ErrorCode != status.ErrorCode)
            try { Diagnostic?.Invoke(status.State, status.ErrorCode); } catch { /* Evidence cannot change sharing. */ }
        if (previous != status)
            try { StatusChanged?.Invoke(); } catch { /* Notification cannot change sharing. */ }
        return status;
    }
    private static bool HardFailure(Account.AccountBridgeHostException error) => error.Code is
        "privacy_publication.account_changed" or "privacy_publication.route_retired";
    private static System.Net.HttpStatusCode? HttpStatus(Exception error) => error switch {
        Account.AccountBridgeHostException e => e.HttpStatus,
        HttpRequestException e => e.StatusCode,
        _ => null
    };
    private static bool Recoverable(Exception error)
    {
        if (error is Account.AccountBridgeHostException hard && HardFailure(hard)) return false;
        return error is not (LocalPrivacyException or IOException or UnauthorizedAccessException or System.Security.SecurityException);
    }
    private static bool ShortRetry(Exception error)
    {
        if (error is Auth.ScmApiUnavailableException { StatusCode: null }) return false;
        if (HttpStatus(error) is { } status && ((int)status is 401 or 408 or 429 or >= 500 and <= 599)) return true;
        // Caller cancellation is temporary; lifetime retirement is handled by
        // the caller. Every retry rechecks owner, generation and handle.
        return error is HttpRequestException { StatusCode: null } or OperationCanceledException or TimeoutException or
            Account.AccountBridgeHostException { Code: "privacy_publication.temporarily_unavailable" or
                "privacy_publication.identity_unavailable" or Account.AccountBridgeStableErrors.ReauthorizationRequired };
    }
    private static string StableError(Exception error) => error switch {
        LocalPrivacyOwnerUnavailableException => "privacy_local.owner_unavailable",
        LocalPrivacyReadUnavailableException => "privacy_local.read_unavailable",
        LocalPrivacyException e => e.Code,
        Account.AccountBridgeHostException e when HardFailure(e) => e.Code,
        _ when HttpStatus(error) == System.Net.HttpStatusCode.Forbidden => "privacy_publication.forbidden",
        _ when HttpStatus(error) is System.Net.HttpStatusCode.BadRequest or System.Net.HttpStatusCode.NotFound => "privacy_publication.rejected",
        _ when HttpStatus(error) == System.Net.HttpStatusCode.Unauthorized => "privacy_publication.identity_unavailable",
        _ when HttpStatus(error) == System.Net.HttpStatusCode.RequestTimeout => "privacy_publication.timeout",
        _ when HttpStatus(error) == System.Net.HttpStatusCode.TooManyRequests => "privacy_publication.rate_limited",
        _ when HttpStatus(error) is { } status && (int)status is >= 500 and <= 599 => "privacy_publication.server_error",
        Account.AccountBridgeHostException { Code: Account.AccountBridgeStableErrors.ReauthorizationRequired } => "privacy_publication.identity_unavailable",
        Account.AccountBridgeHostException e => e.Code,
        Auth.ScmApiUnavailableException => "privacy_publication.unavailable",
        Auth.ScmApiRateLimitException => "privacy_publication.rate_limited",
        Auth.ScmApiProtocolException or JsonException => "privacy_publication.response_invalid",
        HttpRequestException { StatusCode: null } => "privacy_publication.network_unavailable",
        OperationCanceledException or TimeoutException => "privacy_publication.timeout",
        _ => "privacy_publication.unavailable"
    };
    private void ResetRetry() { _retryFailures = 0; _longRetryFailures = 0; _retryAfter = default; _retryRevision = null; _retryError = null; }
    private void ScheduleRetry(long revision, Exception error)
    {
        _retryRevision = revision;
        _retryError = StableError(error);
        var seconds = ShortRetry(error) ? Math.Min(60, 5 * (1 << Math.Min(_retryFailures++, 4)))
            : new[] { 60, 300, 900 }[Math.Min(_longRetryFailures++, 2)];
        _retryAfter = _clock.GetUtcNow().AddSeconds(seconds);
    }
}





