namespace StarBridge.HostRuntime.Account;

using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;
using System.Text.Json;

internal sealed record AccountBridgeDispatchResult(
    BridgeEnvelope Response,
    IReadOnlyList<BridgeEnvelope> Events);

/// <summary>
/// Converts the account host's narrow projections into the frozen Bridge v1
/// wire shape. Callers must send Response before Events so a successful
/// account transition completes before account.changed advances generation.
/// </summary>
internal sealed partial class AccountBridgeDispatcher : IDisposable
{
    private readonly IAccountBridgeHost _host;
    private readonly string[] _profileActions;
    private readonly AccountDispatchGate _dispatchGate = new();
    private readonly object _eventGate = new();
    private readonly List<BridgeEnvelope> _pendingEvents = [];
    private long _eventSequence;
    private int _activeDispatches;
    private bool _disposed;
    private readonly object _activityGate = new();
    private readonly Dictionary<string, (string Id, long Generation, CancellationTokenSource Source)> _activityCancellations = new();

    internal AccountBridgeDispatcher(
        IAccountBridgeHost host, IReadOnlyCollection<string>? enabledRequests = null)
    {
        _host = host ?? throw new ArgumentNullException(nameof(host));
        _profileActions = new[] {
            AccountBridgeRequestNames.PatchPreferences, AccountBridgeRequestNames.ClearProfileCache
        }.Where(name => enabledRequests?.Contains(name) == true).ToArray();
        _host.AccountChanged += OnAccountChanged;
        if (_host is ScmAccountBridgeHost scm) scm.GameIdentityChanged += OnGameIdentityChanged;
    }

    /// <summary>
    /// Publishes account invalidations that happen outside a request. The pipe
    /// owner forwards these immediately; request-scoped transitions remain in
    /// <see cref="AccountBridgeDispatchResult.Events"/> so the response can be
    /// written first.
    /// </summary>
    internal event Action<BridgeEnvelope>? EventReady;

    internal BridgeEnvelope DomainInvalidation(string name, long generation)
    {
        lock (_eventGate)
            return BridgeEnvelope.Event(name, generation, ++_eventSequence, new { schemaVersion = AccountBridgeSchema.Version });
    }

    internal void PublishDomainInvalidation(string name, long generation)
        => PublishDomainEvent(name, generation, new { schemaVersion = AccountBridgeSchema.Version });

    /// <summary>A live event (trade-chat pushes) that does not wait for in-flight dispatches to finish.
    /// Flutter drops any event older than one it has seen, so it never jumps ahead of events already
    /// queued: then it joins that queue instead. Receivers merge by message id, so order is free.</summary>
    internal void PublishLiveEvent(string name, long generation, object payload)
    {
        if (JsonSerializer.SerializeToUtf8Bytes(BridgeEnvelope.Event(name, generation, 0, payload), BridgeProtocol.JsonOptions).Length > BridgeProtocol.MaximumFrameBytes) return;
        BridgeEnvelope frame;
        Action<BridgeEnvelope>? publish = null;
        lock (_eventGate)
        {
            if (_disposed || generation != _host.Generation) return;
            frame = BridgeEnvelope.Event(name, generation, ++_eventSequence, payload);
            if (_pendingEvents.Count != 0) _pendingEvents.Add(frame);
            else publish = EventReady;
        }
        publish?.Invoke(frame);
    }

    internal void PublishRestoreDisplayProgress(long generation, object payload, Func<bool> current)
        => PublishDisplayProgress("account.restoreDisplay", generation, payload, current);

    internal void PublishFriendsDisplayProgress(long generation, object payload, Func<bool> current)
        => PublishDisplayProgress("friends.readDisplay", generation, payload, current);

    private void PublishDisplayProgress(string name, long generation, object payload, Func<bool> current)
    {
        if (!current()) return;
        BridgeEnvelope frame;
        lock (_eventGate)
        {
            if (_disposed || generation != _host.Generation || _pendingEvents.Count != 0) return;
            frame = BridgeEnvelope.Event(name, generation, ++_eventSequence, payload);
        }
        // A display-only progress frame must not wait behind the root's final
        // response. All account/domain invalidations keep their original queue.
        if (JsonSerializer.SerializeToUtf8Bytes(frame, BridgeProtocol.JsonOptions).Length > BridgeProtocol.MaximumFrameBytes) return;
        if (current() && generation == _host.Generation) EventReady?.Invoke(frame);
    }

    internal void PublishDomainEvent(string name, long generation, object payload)
    {
        BridgeEnvelope envelope;
        Action<BridgeEnvelope>? publish = null;
        lock (_eventGate)
        {
            if (_disposed || generation != _host.Generation) return;
            envelope = BridgeEnvelope.Event(name, generation, ++_eventSequence, payload);
            if (_activeDispatches > 0) _pendingEvents.Add(envelope);
            else publish = EventReady;
        }
        if (publish is not null)
            foreach (Action<BridgeEnvelope> subscriber in publish.GetInvocationList())
                try { subscriber(envelope); } catch { /* A subscriber cannot consume sibling achievement deliveries. */ }
    }

    internal async Task<AccountBridgeDispatchResult> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        using var currentDiagnostic = request.Name == AccountBridgeRequestNames.GetCurrent ? new AccountCurrentDiagnostics() : null;
        if (request.Name == "bridge.cancel") return CancelActivityWait(request);
        if (request.Name is AccountBridgeRequestNames.WaitSocialActivity or AccountBridgeRequestNames.WaitCommunityActivity or AccountBridgeRequestNames.WaitOfficialFleetActivity or AccountBridgeRequestNames.WaitOfficialFleetRuntimeActivity)
            return await DispatchActivityWaitAsync(request, cancellationToken);
        if (request.Name == AccountBridgeRequestNames.CancelLogin)
        {
            return await DispatchLoginCancellationAsync(request);
        }
        if (GameIdentityBridge.IsRequest(request.Name))
            return await DispatchGameIdentityAsync(request, cancellationToken).ConfigureAwait(false);
        if ((request.Name == AccountBridgeRequestNames.GetOfficialFleetPublicProfile &&
            _host is IAccountBridgeOfficialFleetProfileReader) ||
            (request.Name is AccountBridgeRequestNames.ReadProfileDisplayCache or AccountBridgeRequestNames.GetProfileTimeZoneDirectory &&
            _host is IAccountBridgeStagedProfileReader))
            return await DispatchIndependentProjectionAsync(request, cancellationToken);

        var concurrentRead = IsIndependentRead(request.Name) && (_host.SupportsConcurrentReads ||
            (IsResourceRead(request.Name) && _host is IAccountBridgeConcurrentResourceReads { SupportsConcurrentResourceReads: true }));
        bool drainEvents;
        lock (_eventGate) drainEvents = _pendingEvents.Count > 0;
        if (currentDiagnostic is not null)
        {
            _dispatchGate.Observe(currentDiagnostic);
            if (drainEvents) currentDiagnostic.Reason = CurrentProjectionReason.pendingEvents;
        }
        if (request.Name == AccountBridgeRequestNames.GetCurrent && !drainEvents &&
            _host is IAccountBridgeCurrentProjection fast && TryProjectCurrent(request, fast, currentDiagnostic!) is { } projected)
            return projected;
        // Once an invalidation is pending, fence later readers so a continuous
        // stream of reads cannot indefinitely postpone its delivery.
#if STARBRIDGE_SESSION_PROBE || STARBRIDGE_MEMBER_READ_PROBE
        using var timing = AccountReadTiming.Begin(request.Name, MemberReadProbeSchema(request.Name, request.Payload));
#else
        using var timing = AccountReadTiming.Begin(request.Name);
#endif
        var waiting = AccountReadTiming.Measure(AccountReadPhase.DispatchWait);
        IAsyncDisposable admission;
        using (waiting)
        {
#if STARBRIDGE_SESSION_PROBE || STARBRIDGE_MEMBER_READ_PROBE
            try
            {
#endif
                currentDiagnostic?.Waiting();
                admission = await _dispatchGate.EnterAsync(Access(request.Name, concurrentRead, drainEvents), cancellationToken);
                currentDiagnostic?.Working();
                waiting?.Returned();
#if STARBRIDGE_SESSION_PROBE || STARBRIDGE_MEMBER_READ_PROBE
            }
            catch (OperationCanceledException)
            {
                AccountReadTiming.Response(request.Name, "cancelled", "bridge.cancelled");
                throw;
            }
#endif
        }
        await using var lease = admission;
        using var working = AccountReadTiming.Measure(AccountReadPhase.DispatchWork);
        try
        {
            BeginDispatchEventCollection();
            var response = await DispatchCoreAsync(request, cancellationToken);
            // A read may have been invalidated by another reader's credential
            // failure or an external account transition while it awaited I/O.
            // GetCurrent itself can restore the session and owns that transition.
            if (concurrentRead && request.Name != AccountBridgeRequestNames.GetCurrent &&
                request.SessionGeneration != _host.Generation)
                throw new BridgeStaleGenerationException(request.SessionGeneration, _host.Generation);
            var result = Result(response);
            working?.Returned();
            return result;
        }
        catch (AccountBridgeHostException exception)
        {
            Friends.FriendsReadProbeDiagnostics.DispatchFailure(request.Name, exception);
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(exception.Code, "Account operation failed.", exception.Retryable)) with
                {
                    Payload = exception.Code == "membershipEvidenceStale" && exception.MembershipUpdatedAt is { } updated
                        ? JsonSerializer.SerializeToElement(new { schemaVersion = 1, reason = exception.Code, membershipUpdatedAt = updated })
                        : BridgePayload.Empty
                });
        }
        catch (BridgeProtocolException exception)
        {
            Friends.FriendsReadProbeDiagnostics.DispatchFailure(request.Name, exception);
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(exception.Code, "Bridge request was rejected.")));
        }
        catch (OperationCanceledException) when (request.Name == AccountBridgeRequestNames.Login)
        {
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(AccountBridgeStableErrors.LoginCancelled, "Sign-in was cancelled.")));
        }
        catch (OperationCanceledException exception)
        {
            Friends.FriendsReadProbeDiagnostics.DispatchFailure(request.Name, exception);
            return Result(BridgeEnvelope.CancelledResponse(request));
        }
        catch (Exception exception)
        {
            Friends.FriendsReadProbeDiagnostics.DispatchFailure(request.Name, exception);
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(BridgeErrorCodes.HostError, "Account operation failed.")));
        }
    }

    // This one bounded, non-mutating wait must never hold up account writes.
    private async Task<AccountBridgeDispatchResult> DispatchActivityWaitAsync(BridgeEnvelope request, CancellationToken token)
    {
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(token);
        lock (_activityGate)
        {
            if (_activityCancellations.ContainsKey(request.Name))
                return new(BridgeEnvelope.ErrorResponse(request, new("bridge.backpressure", "Activity wait already pending.", true)), []);
            _activityCancellations.Add(request.Name, (request.CorrelationId!, request.SessionGeneration, lifetime));
        }
        try {
            var response = await DispatchCoreAsync(request, lifetime.Token);
            if (request.SessionGeneration != _host.Generation)
                throw new BridgeStaleGenerationException(request.SessionGeneration, _host.Generation);
            return new(response, []);
        } catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (AccountBridgeHostException e) { return new(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Activity unavailable.", e.Retryable)), []); }
        catch (BridgeProtocolException e) { return new(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Activity rejected.")), []); }
        catch (Exception) { return new(BridgeEnvelope.ErrorResponse(request, new("friends.read_unavailable", "Activity unavailable.", true)), []); }
        finally {
            lock (_activityGate) _activityCancellations.Remove(request.Name);
        }
    }

    private AccountBridgeDispatchResult CancelActivityWait(BridgeEnvelope request)
    {
        try {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext != null ||
                request.Payload.EnumerateObject().Count() != 1) throw new ArgumentException();
            var id = request.Payload.GetProperty("targetCorrelationId").GetString();
            var cancelled = false;
            lock (_activityGate) {
                foreach (var active in _activityCancellations.Values.Where(active => active.Id == id && active.Generation == request.SessionGeneration)) {
                    active.Source.Cancel();
                    cancelled = true;
                }
            }
            return new(BridgeEnvelope.Response(request, new { cancelled }), []);
        } catch (Exception e) when (e is BridgeProtocolException or InvalidOperationException or ArgumentException or KeyNotFoundException) {
            return new(BridgeEnvelope.ErrorResponse(request, new("bridge.invalid_request", "Invalid cancellation.")), []);
        }
    }

    // Explicitly audited read-only surfaces, not a suffix/prefix heuristic.
    // Authentication and writes, and unaudited reads, remain exclusive.
    private static bool IsIndependentRead(string name) => name is
        AccountBridgeRequestNames.GetCurrent or
        // A synchronous current-session projection, with no credential refresh
        // or mutation. The opt-in host and generation/event fences still apply.
        AccountBridgeRequestNames.GetGameIdentityPolicy or
        AccountBridgeRequestNames.ReadFriends or
        AccountBridgeRequestNames.ReadCommunities or
        AccountBridgeRequestNames.ReadCommunityWorkspace or
        AccountBridgeRequestNames.ReadCommunityMedia;

    // DL-129 option 3: the subset an SCM session may overlap. Current and the
    // identity policy project shared session state and stay exclusive there.
    private static bool IsResourceRead(string name) => name is
        AccountBridgeRequestNames.ReadFriends or
        AccountBridgeRequestNames.ReadCommunities or
        AccountBridgeRequestNames.ReadCommunityWorkspace or
        AccountBridgeRequestNames.ReadCommunityMedia;

    // DL-129: a repeated current read beside queued or running reads, never
    // beside or ahead of an account mutation. Null takes the ordinary queue.
    private AccountBridgeDispatchResult? TryProjectCurrent(BridgeEnvelope request, IAccountBridgeCurrentProjection host, AccountCurrentDiagnostics diagnostic)
    {
        if (!_dispatchGate.TryEnterProjection(out var lease, out var reason)) { diagnostic.Reason = reason; return null; }
        try
        {
            diagnostic.Working();
            var projection = host is ScmAccountBridgeHost scm ? scm.TryProjectCurrent(out reason) : host.TryProjectCurrent();
            diagnostic.Reason = host is ScmAccountBridgeHost ? reason : CurrentProjectionReason.hostDeclined;
            if (projection is null) return null;
            diagnostic.Projected = true;
            diagnostic.Reason = CurrentProjectionReason.none;
            BeginDispatchEventCollection();
            return Result(ToSessionResponse(request, projection));
        }
        finally { _ = lease.DisposeAsync(); }
    }

    // Reads may be reordered among themselves by priority; they never pass a
    // queued barrier. An event-draining read stays a barrier so a continuous
    // stream of reads cannot postpone invalidation delivery (DL-129).
    private static AccountDispatchAccess Access(string name, bool concurrentRead, bool drainEvents)
    {
        if (drainEvents || ReadPriority(name) is not { } priority) return AccountDispatchAccess.Barrier;
        return new(concurrentRead, true, priority);
    }

    private static AccountDispatchPriority? ReadPriority(string name) => name switch
    {
        // What the visible page or shell is waiting for right now.
        AccountBridgeRequestNames.GetCurrent or AccountBridgeRequestNames.GetGameIdentityPolicy or
        AccountBridgeRequestNames.ReadFriends or AccountBridgeRequestNames.ReadCommunities or
        AccountBridgeRequestNames.ReadCommunityWorkspace or
        // Shell call sign and photo; startup now waits for it (2026-10-20).
        AccountBridgeRequestNames.ReadAvatar or
        // Messages window directory and history (2026-10-21). One GET; the
        // conversation targets and cursors it updates sit under the reader's
        // own lock, and sends/mark-read stay barriers it can never pass. Two
        // message reads keep their order (same priority, first come first).
        AccountBridgeRequestNames.ReadDirectMessages => AccountDispatchPriority.Foreground,
        AccountBridgeRequestNames.ReadCommunityChat or
        // Audited pure reads: one GET plus the shared session write every read
        // performs; inbox and rooms refresh only their own read leases. Startup
        // sends them with the shell's first reads, and as barriers they held the
        // organization directory behind all of them (DL-137). Their writes stay
        // barriers, and nothing passes a queued mutation.
        AccountBridgeRequestNames.ReadNotificationInbox or AccountBridgeRequestNames.GetOfficialFleetIdentity or
        AccountBridgeRequestNames.GetPartyRooms or AccountBridgeRequestNames.ReadDirectMessagePrivacy or
        AccountBridgeRequestNames.ReadFriendRequestPrivacy or
        AccountBridgeRequestNames.ReadRecentlyPlayedPrivacy => AccountDispatchPriority.Normal,
        // Optional logos and avatars: text is already shown without them (DL-117).
        AccountBridgeRequestNames.ReadCommunityMedia => AccountDispatchPriority.Background,
        _ => null
    };

    private async Task<AccountBridgeDispatchResult> DispatchIndependentProjectionAsync(BridgeEnvelope request, CancellationToken token)
    {
        // Only this public, credential-free read leaves the account dispatch
        // gate. It cannot mutate identity or publish account transitions, so it
        // must not postpone a writer's response-before-events delivery either.
        try {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var response = await DispatchCoreAsync(request, token);
            if (request.SessionGeneration != _host.Generation)
                throw new BridgeStaleGenerationException(request.SessionGeneration, _host.Generation);
            return new(response, []);
        }
        catch (AccountBridgeHostException error) {
            return new(BridgeEnvelope.ErrorResponse(request, new(error.Code, "Account operation failed.", error.Retryable)), []);
        }
        catch (BridgeProtocolException error) {
            return new(BridgeEnvelope.ErrorResponse(request, new(error.Code, "Bridge request was rejected.")), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception) { return new(BridgeEnvelope.ErrorResponse(request, new(BridgeErrorCodes.HostError, "Account operation failed.")), []); }
    }

    private async Task<AccountBridgeDispatchResult> DispatchLoginCancellationAsync(
        BridgeEnvelope request)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            RequireSchemaVersion(request.Payload);
            if (request.SessionGeneration != _host.Generation)
            {
                throw new BridgeStaleGenerationException(
                    request.SessionGeneration,
                    _host.Generation);
            }

            return new AccountBridgeDispatchResult(
                await CancelLoginAsync(request),
                []);
        }
        catch (BridgeProtocolException exception)
        {
            return new AccountBridgeDispatchResult(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(exception.Code, "Bridge request was rejected.")),
                []);
        }
        catch (Exception)
        {
            return new AccountBridgeDispatchResult(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(BridgeErrorCodes.Disconnected, "Account host is unavailable.", true)),
                []);
        }
    }

    private async Task<BridgeEnvelope> DispatchCoreAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        BridgeEnvelopeValidator.ValidateWireShape(request);
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        if (request.MessageType != BridgeMessageTypes.Request)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Account dispatcher only accepts requests.");
        }

        RequireSchemaVersion(request.Payload, request.Name is AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers or
            AccountBridgeRequestNames.WaitOfficialFleetRuntimeActivity ? 2 : AccountBridgeSchema.Version);
        if (request.Name == AccountBridgeRequestNames.GetCurrent) ValidateRestoreDisplayOption(request);
        if (request.SessionGeneration != _host.Generation)
        {
            throw new BridgeStaleGenerationException(
                request.SessionGeneration,
                _host.Generation);
        }

        BridgeEnvelopeValidator.RequireAccountContext(request.Name, request.AccountContext);
        return request.Name switch
        {
            GameIdentityBridge.RequestCode or GameIdentityBridge.Verify or GameIdentityBridge.OpenProfile =>
                _host is ScmAccountBridgeHost identityHost
                    ? BridgeEnvelope.Response(request, await identityHost.GameIdentityAsync(RequireCurrentContext(request),
                        request.SessionGeneration, request.Name, request.Payload, cancellationToken))
                    : throw new AccountBridgeHostException(BridgeErrorCodes.CapabilityUnavailable),
            AccountBridgeRequestNames.RedeemLegacyEntitlements =>
                BridgeEnvelope.Response(request, await _host.RedeemLegacyEntitlementsAsync(request.AccountContext!, request.Payload, cancellationToken)),
            AccountBridgeRequestNames.LoginLegacy =>
                request.AccountContext is not null
                    ? throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Legacy login must not carry an SCM context.")
                    : BridgeEnvelope.Response(request, await _host.LoginLegacyAsync(request.Payload, request.SessionGeneration, cancellationToken)),
            AccountBridgeRequestNames.SendPasswordResetCode or AccountBridgeRequestNames.ConfirmPasswordReset =>
                request.AccountContext is not null
                    ? throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Password recovery must not carry an account context.")
                    : BridgeEnvelope.Response(request, await _host.RecoverPasswordAsync(request.Name, request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetLegacyProfileMigrationStatus or
                AccountBridgeRequestNames.PreviewLegacyProfileMigration or
                AccountBridgeRequestNames.ConfirmLegacyProfileMigration =>
                await DispatchMigrationAsync(request, cancellationToken),
            AccountBridgeRequestNames.GetCurrent =>
                ToSessionResponse(request, await _host.GetCurrentAsync(cancellationToken)),
            "account.achievementIdeaSubmit" =>
                BridgeEnvelope.Response(request, await _host.SubmitAchievementIdeaAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            "account.supportRead" or "account.supportClaim" =>
                BridgeEnvelope.Response(request, await _host.DailySupportAsync(RequireCurrentContext(request),
                    request.Payload, request.Name == "account.supportClaim", cancellationToken)),
            AccountBridgeRequestNames.UpdateAvatar =>
                await UpdateAvatarAsync(request, cancellationToken),
            AccountBridgeRequestNames.UpdateCallSign =>
                await UpdateCallSignAsync(request, cancellationToken),
            AccountBridgeRequestNames.ReadAvatar =>
                BridgeEnvelope.Response(request, await _host.ReadAvatarAsync(RequireCurrentContext(request), cancellationToken)),
            AccountBridgeRequestNames.Login =>
                ToSessionResponse(request, await _host.LoginAsync(cancellationToken)),
            AccountBridgeRequestNames.CancelLogin =>
                await CancelLoginAsync(request),
            AccountBridgeRequestNames.Logout =>
                await LogoutAsync(request, cancellationToken),
            AccountBridgeRequestNames.GetProfile =>
                ToProfileResponse(
                    request,
                    await _host.GetProfileAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            AccountBridgeRequestNames.ReadProfileDisplayCache or AccountBridgeRequestNames.GetProfileDisplayData or
                AccountBridgeRequestNames.GetProfileTimeZoneDirectory when _host is IAccountBridgeStagedProfileReader staged =>
                await DispatchStagedProfileAsync(request, staged, cancellationToken),
            AccountBridgeRequestNames.GetPersonalProfile =>
                ToPersonalProfileResponse(
                    request,
                    await _host.GetPersonalProfileAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            "personalProfile.readVisibility" or "personalProfile.saveVisibility" =>
                BridgeEnvelope.Response(request, await _host.ProfileVisibilityAsync(
                    RequireCurrentContext(request), request.Payload,
                    request.Name == "personalProfile.saveVisibility", cancellationToken)),
            "personalProfile.readBackground" or "personalProfile.saveBackground" =>
                BridgeEnvelope.Response(request, await _host.ProfileBackgroundAsync(
                    RequireCurrentContext(request), request.Payload,
                    request.Name == "personalProfile.saveBackground", cancellationToken)),
            "communities.memberPersonalProfile" =>
                await ToVisitorProfileResponseAsync(request, () => _host.ReadMemberPersonalProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            "users.profile" =>
                await ToVisitorProfileResponseAsync(request, () => _host.ReadUserProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            "users.social" =>
                BridgeEnvelope.Response(request, await _host.ReadUserSocialAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.UpdatePersonalProfile =>
                ToPersonalProfileResponse(
                    request,
                    await _host.UpdatePersonalProfileAsync(
                        RequireCurrentContext(request),
                        ParsePersonalProfileUpdate(request.Payload),
                        cancellationToken)),
            "personalProfile.updatePresentation" =>
                ToPersonalProfileResponse(request, await _host.UpdatePagePresentationAsync(
                    RequireCurrentContext(request), PageEditBridgeContract.Read(request.Payload), cancellationToken)),
            AccountBridgeRequestNames.GetOfficialFleet =>
                ToOfficialFleetResponse(
                    request,
                    await _host.GetOfficialFleetAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            AccountBridgeRequestNames.GetOfficialFleetIdentity =>
                ToOfficialFleetResponse(request, await _host.GetOfficialFleetIdentityAsync(RequireCurrentContext(request), cancellationToken)),
            AccountBridgeRequestNames.GetOfficialFleetPublicProfile when _host is IAccountBridgeOfficialFleetProfileReader reader =>
                ToOfficialFleetPublicProfileResponse(request, await reader.GetOfficialFleetPublicProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.OfficialFleetCommunication =>
                BridgeEnvelope.Response(request, await _host.OfficialFleetCommunicationAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetRankPolicy or AccountBridgeRequestNames.WriteOfficialFleetRankPolicy or
                AccountBridgeRequestNames.UpdateOfficialFleetRolePermissions or AccountBridgeRequestNames.ReadOfficialFleetMemberRoles or
                AccountBridgeRequestNames.AssignOfficialFleetRole or AccountBridgeRequestNames.RevokeOfficialFleetRole or
                AccountBridgeRequestNames.ReadOfficialFleetGovernanceAudit or AccountBridgeRequestNames.ReadOfficialFleetGovernanceOutcome =>
                BridgeEnvelope.Response(request, await _host.OfficialFleetGovernanceManagementAsync(RequireCurrentContext(request),
                    request.Payload, request.Name["officialFleet.".Length..], cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetRoleTemplates =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetRoleTemplatesAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ManageOfficialFleetRoleTemplates =>
                BridgeEnvelope.Response(request, await _host.ManageOfficialFleetRoleTemplatesAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetRoleTemplateOutcome =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetRoleTemplateOutcomeAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetGovernanceContext =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetGovernanceContextAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ActivateOfficialFleetGovernance =>
                BridgeEnvelope.Response(request, await _host.ActivateOfficialFleetGovernanceAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.RevokeOfficialFleetGovernanceActivation =>
                BridgeEnvelope.Response(request, await _host.RevokeOfficialFleetGovernanceActivationAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetAnnouncementEditor =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetAnnouncementEditorAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ManageOfficialFleetAnnouncements =>
                BridgeEnvelope.Response(request, await _host.ManageOfficialFleetAnnouncementsAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetAnnouncementOutcome =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetAnnouncementOutcomeAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.OfficialFleetRally =>
                BridgeEnvelope.Response(request, await _host.OfficialFleetRallyAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.WaitOfficialFleetActivity =>
                BridgeEnvelope.Response(request, await _host.WaitOfficialFleetActivityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetShipImage =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetShipImageAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReportOfficialFleetShipImage =>
                BridgeEnvelope.Response(request, await _host.ReportOfficialFleetShipImageAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetShipImageReportStatus =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetShipImageReportStatusAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetShips =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetShipsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetHangarSharing =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetHangarSharingAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadOfficialFleetHangarSharingPage =>
                BridgeEnvelope.Response(request, await _host.ReadOfficialFleetHangarSharingPageAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveOfficialFleetHangarSharing =>
                BridgeEnvelope.Response(request, await _host.SaveOfficialFleetHangarSharingAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.WaitOfficialFleetRuntimeActivity =>
                BridgeEnvelope.Response(request, await _host.WaitOfficialFleetRuntimeActivityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers =>
                BridgeEnvelope.Response(request, await _host.GetOfficialFleetRuntimeMembersAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetOfficialFleetMembers =>
                BridgeEnvelope.Response(request, await _host.GetOfficialFleetMembersAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetPartyRooms =>
                BridgeEnvelope.Response(request, await _host.GetPartyRoomsAsync(
                    RequireCurrentContext(request), cancellationToken)),
            AccountBridgeRequestNames.ExecuteFriend =>
                BridgeEnvelope.Response(request, await _host.ExecuteFriendAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadDirectMessages =>
                BridgeEnvelope.Response(request, await _host.ReadDirectMessagesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.WaitSocialActivity =>
                BridgeEnvelope.Response(request, await _host.WaitSocialActivityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.WaitCommunityActivity =>
                BridgeEnvelope.Response(request, await _host.WaitCommunityActivityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadDirectMessagePrivacy =>
                BridgeEnvelope.Response(request, await _host.ReadDirectMessagePrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveDirectMessagePrivacy =>
                BridgeEnvelope.Response(request, await _host.SaveDirectMessagePrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadFriendRequestPrivacy =>
                BridgeEnvelope.Response(request, await _host.ReadFriendRequestPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveFriendRequestPrivacy =>
                BridgeEnvelope.Response(request, await _host.SaveFriendRequestPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadRecentlyPlayedPrivacy =>
                BridgeEnvelope.Response(request, await _host.ReadRecentlyPlayedPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveRecentlyPlayedPrivacy =>
                BridgeEnvelope.Response(request, await _host.SaveRecentlyPlayedPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.MarkDirectMessagesRead =>
                BridgeEnvelope.Response(request, await _host.MarkDirectMessagesReadAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SendDirectMessage =>
                BridgeEnvelope.Response(request, await _host.SendDirectMessageAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadFriends =>
                BridgeEnvelope.Response(request, await _host.ReadFriendsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadAccountSafety =>
                BridgeEnvelope.Response(request, await _host.ReadAccountSafetyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadNotificationInbox =>
                BridgeEnvelope.Response(request, await _host.ReadNotificationInboxAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.MarkNotificationInboxRead =>
                BridgeEnvelope.Response(request, await _host.MarkNotificationInboxReadAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SubmitAccountAppeal =>
                BridgeEnvelope.Response(request, await _host.SubmitAccountAppealAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunities =>
                BridgeEnvelope.Response(request, await _host.ReadCommunitiesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ExecuteCommunity =>
                BridgeEnvelope.Response(request, await _host.ExecuteCommunityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetCommunityCreationOptions =>
                BridgeEnvelope.Response(request, await _host.GetCommunityCreationOptionsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.CreateCommunity =>
                BridgeEnvelope.Response(request, await _host.CreateCommunityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityWorkspace =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityWorkspaceAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityLogs =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityLogsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.DeleteCommunityLog =>
                BridgeEnvelope.Response(request, await _host.DeleteCommunityLogAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityDisband =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityDisbandAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityChat =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityChatAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityAnnouncements =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityAnnouncementsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityShips =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityShipsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityHangarSharing =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityHangarSharingAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityHangarSharing =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityHangarSharingAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityShipImage =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityShipImageAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReportCommunityShipImage =>
                BridgeEnvelope.Response(request, await _host.ReportCommunityShipImageAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityAnnouncementDetail =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityAnnouncementDetailAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ManageCommunityAnnouncements =>
                BridgeEnvelope.Response(request, await _host.ManageCommunityAnnouncementsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityChatDetail =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityChatDetailAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.MarkCommunityChatRead =>
                BridgeEnvelope.Response(request, await _host.MarkCommunityChatReadAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SendCommunityChat =>
                BridgeEnvelope.Response(request, await _host.SendCommunityChatAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.DisbandCommunity =>
                BridgeEnvelope.Response(request, await _host.DisbandCommunityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityMedia =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityMediaAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityProfile =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityAdmissions =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityAdmissionsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ManageCommunityAdmissions =>
                BridgeEnvelope.Response(request, await _host.ManageCommunityAdmissionsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityProfile =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityRoles =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityRolesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityMemberRole =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityMemberRoleAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityMemberRole =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityMemberRoleAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityMemberRemoval =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityMemberRemovalAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.RemoveCommunityMember =>
                BridgeEnvelope.Response(request, await _host.RemoveCommunityMemberAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityOwnershipTransfer =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityOwnershipTransferAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.TransferCommunityOwnership =>
                BridgeEnvelope.Response(request, await _host.TransferCommunityOwnershipAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityOwnershipExit =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityOwnershipExitAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.LeaveCommunityWithSuccessor =>
                BridgeEnvelope.Response(request, await _host.LeaveCommunityWithSuccessorAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityRoles =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityRolesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.PreviewCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.PreviewCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.AcceptCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.AcceptCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SendCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.SendCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ResumeCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.ResumeCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityInvitationOutbox =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityInvitationOutboxAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ExecutePartyRoom =>
                BridgeEnvelope.Response(request, await _host.ExecutePartyRoomAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetCompatibilityState =>
                ToCompatibilityResponse(
                    request,
                    await _host.GetCompatibilityStateAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            AccountBridgeRequestNames.LinkLegacyAccount =>
                ToCompatibilityResponse(
                    request,
                    await _host.LinkLegacyAccountAsync(
                        RequireCurrentContext(request),
                        ParseLegacyCredential(request.Payload),
                        cancellationToken)),
            AccountBridgeRequestNames.CreateCompatibilityIdentity =>
                await CreateCompatibilityIdentityAsync(request, cancellationToken),
            AccountBridgeRequestNames.PatchPreferences =>
                ToProfileResponse(
                    request,
                    await _host.PatchPreferencesAsync(
                        RequireCurrentContext(request),
                        ParsePatch(request.Payload),
                        cancellationToken), includesDirectory: false),
            AccountBridgeRequestNames.ClearProfileCache =>
                BridgeEnvelope.Response(
                    request,
                    new
                    {
                        schemaVersion = AccountBridgeSchema.Version,
                        cleared = await _host.ClearProfileCacheAsync(
                            RequireCurrentContext(request),
                            cancellationToken)
                    }),
            AccountBridgeRequestNames.GetGameIdentityPolicy =>
                ToIdentityResponse(
                    request,
                    await _host.GetGameIdentityPolicyAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            AccountBridgeRequestNames.PrepareHandleChange =>
                await PrepareHandleChangeAsync(request, cancellationToken),
            AccountBridgeRequestNames.ConfirmHandleChange => BridgeEnvelope.Response(request,
                await _host.ConfirmHandleChangeAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.CancelHandleChange => BridgeEnvelope.Response(request,
                await _host.CancelHandleChangeAsync(RequireCurrentContext(request), request.Payload, cancellationToken)),
            _ => throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Unsupported account request.")
        };
    }

    private async Task<BridgeEnvelope> PrepareHandleChangeAsync(BridgeEnvelope request, CancellationToken token)
    {
        if (request.Payload.EnumerateObject().Count() != 1 ||
            request.Payload.EnumerateObject().Single().Name != "schemaVersion")
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Unsupported identity handling fields.");
        return BridgeEnvelope.Response(request,
            await _host.PrepareHandleChangeAsync(RequireCurrentContext(request), token));
    }

    private async Task<BridgeEnvelope> CancelLoginAsync(BridgeEnvelope request)
    {
        await _host.CancelLoginAsync();
        return BridgeEnvelope.Response(
            request,
            new { schemaVersion = AccountBridgeSchema.Version, cancelled = true },
            preserveRequestAccountContext: false);
    }

    private async Task<BridgeEnvelope> LogoutAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        await _host.LogoutAsync(RequireCurrentContext(request), cancellationToken);
        return BridgeEnvelope.Response(
            request,
            new { schemaVersion = AccountBridgeSchema.Version, state = "signedOut" },
            preserveRequestAccountContext: false);
    }

    private async Task<BridgeEnvelope> CreateCompatibilityIdentityAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        RejectUnknownProperties(request.Payload, "schemaVersion");
        return ToCompatibilityResponse(
            request,
            await _host.CreateCompatibilityIdentityAsync(
                RequireCurrentContext(request),
                cancellationToken));
    }

    private async Task<BridgeEnvelope> UpdateAvatarAsync(BridgeEnvelope request, CancellationToken token)
    {
        var result = await _host.UpdateAvatarAsync(RequireCurrentContext(request), request.Payload, token);
        PublishDomainInvalidation("account.avatarChanged", _host.Generation);
        return BridgeEnvelope.Response(request, result);
    }

    private async Task<BridgeEnvelope> UpdateCallSignAsync(BridgeEnvelope request, CancellationToken token)
    {
        var result = await _host.UpdateCallSignAsync(RequireCurrentContext(request), request.Payload, token);
        PublishDomainInvalidation("account.presentationChanged", _host.Generation);
        return BridgeEnvelope.Response(request, result);
    }

    private static BridgeEnvelope ToSessionResponse(
        BridgeEnvelope request,
        AccountBridgeSessionProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                state = projection.State,
                displayName = projection.DisplayName,
                avatarUrl = projection.AvatarUrl,
                avatarImageData = projection.AvatarImageData,
                maskedAccount = projection.MaskedAccount
            },
            projection.Context,
            preserveRequestAccountContext: false);

    private BridgeEnvelope ToProfileResponse(
        BridgeEnvelope request,
        AccountBridgeProfileProjection projection, bool allowPreferenceWrite = true, bool includesDirectory = true) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                profile = projection.Profile,
                source = projection.Source,
                cachedAtUtc = projection.CachedAtUtc,
                observedAtUtc = projection.ObservedAtUtc,
                preferencesPolicy = new
                {
                    locales = projection.Locales,
                    timeZones = includesDirectory ? projection.TimeZones : [],
                    directoryIncluded = includesDirectory,
                    availableActions = _profileActions.Where(action => allowPreferenceWrite || action != AccountBridgeRequestNames.PatchPreferences).ToArray()
                }
            });

    // DEPLOY-QUEUE §4: outside the visibility a visitor gets the always-public header, not an error.
    private static async Task<BridgeEnvelope> ToVisitorProfileResponseAsync(
        BridgeEnvelope request, Func<Task<StarBridge.Core.Profiles.PersonalProfileDocumentContract>> read)
    {
        try { return ToPersonalProfileResponse(request, await read(), editable: false); }
        catch (PersonalProfileRestrictedException restricted)
        { return BridgeEnvelope.Response(request, restricted.Header.ToBridge()); }
    }

    private static BridgeEnvelope ToPersonalProfileResponse(
        BridgeEnvelope request,
        StarBridge.Core.Profiles.PersonalProfileDocumentContract profile, bool editable = true) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                editable,
                profile = new
                {
                    isPublic = profile.IsPublic,
                    visibility = profile.Visibility,
                    revision = profile.Revision,
                    avatarStyle = profile.AvatarStyle,
                    wallpaperId = profile.WallpaperId,
                    presentation = profile.Presentation,
                    identity = new
                    {
                        callSign = profile.Identity.Callsign,
                        gameHandle = profile.Identity.GameId,
                        avatarAssetId = profile.Identity.AvatarAssetId
                    },
                    content = profile.Content,
                    // Keep the typed additive LogoUrl from the authorized visitor read.
                    fleetAffiliation = profile.FleetAffiliation,
                    fleetAffiliationStatus = profile.FleetAffiliationStatus,
                    hangar = profile.Hangar is null ? null : new {
                        ships = profile.Hangar.Ships.Select(Hangar.HangarShipNames.PresentProfile).ToArray()
                    },
                    gameplayStatistics = profile.GameplayStatistics,
                    isGameplayStatisticsPublic = profile.IsGameplayStatisticsPublic
                }
            });

    private async Task<BridgeEnvelope> DispatchMigrationAsync(BridgeEnvelope request, CancellationToken token)
    {
        var action = request.Name switch
        {
            AccountBridgeRequestNames.PreviewLegacyProfileMigration => "preview",
            AccountBridgeRequestNames.ConfirmLegacyProfileMigration => "confirm",
            _ => "status"
        };
        string? previewId = null;
        var replaceExisting = false;
        StarBridge.HostRuntime.Auth.LegacyProfileCredential? credentials = null;
        StarBridge.HostRuntime.Auth.LegacyProfileImportSelection? selection = null;
        if (request.Payload.TryGetProperty("selection", out var selected))
        {
            try
            {
                if (action != "preview" || selected.ValueKind != JsonValueKind.Object ||
                    selected.EnumerateObject().Count() is not (3 or 4 or 5 or 6) ||
                    selected.EnumerateObject().Select(property => property.Name).Distinct().Count() != selected.EnumerateObject().Count() ||
                    selected.EnumerateObject().Any(property => property.Name is not
                        ("modules" or "replaceModules" or "useLegacyCallSign" or "useLegacyAvatar" or "previousCompletedPreviewId" or "replaceAllDisplayContent")))
                    throw new ArgumentException();
                selection = new(selected.GetProperty("modules").EnumerateArray().Select(value => value.GetString()!).ToArray(),
                    selected.GetProperty("replaceModules").EnumerateArray().Select(value => value.GetString()!).ToArray(),
                    selected.GetProperty("useLegacyCallSign").GetBoolean(),
                    selected.TryGetProperty("useLegacyAvatar", out var useAvatar) && useAvatar.GetBoolean(),
                    selected.TryGetProperty("previousCompletedPreviewId", out var previous) ? previous.GetString() : null,
                    selected.TryGetProperty("replaceAllDisplayContent", out var full) && full.GetBoolean());
                selection.Validate();
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException or KeyNotFoundException)
            { throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Invalid module import selection."); }
        }
        if (action == "preview" && request.Payload.TryGetProperty("accountName", out _))
        {
            var accountName = ReadBoundedString(request.Payload, "accountName", 254);
            if (!request.Payload.TryGetProperty("password", out var secret) ||
                secret.ValueKind != JsonValueKind.String || secret.GetString() is not { Length: > 0 and <= 1024 } password)
                throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Legacy credential is required.");
            credentials = new(accountName, password);
        }
        if (action == "confirm")
        {
            previewId = ReadBoundedString(request.Payload, "previewId", 64);
            if (string.IsNullOrWhiteSpace(previewId) ||
                !request.Payload.TryGetProperty("replaceExisting", out var replace) ||
                replace.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Migration consent is required.");
            replaceExisting = replace.GetBoolean();
        }
        var view = await _host.MigrateLegacyProfileAsync(
            RequireCurrentContext(request), action, previewId, replaceExisting, token, credentials, selection);
        if (action == "confirm" && view.State == "completed")
        {
            if (view.Choices?.UseLegacyAvatar == true)
                PublishDomainInvalidation("account.avatarChanged", _host.Generation);
            lock (_eventGate)
                _pendingEvents.Add(BridgeEnvelope.Event("personalProfile.changed", _host.Generation,
                    ++_eventSequence, new { schemaVersion = AccountBridgeSchema.Version }));
        }
        return BridgeEnvelope.Response(request, new { schemaVersion = AccountBridgeSchema.Version, migration = view });
    }

    private static BridgeEnvelope ToOfficialFleetResponse(
        BridgeEnvelope request,
        AccountBridgeOfficialFleetProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                state = projection.State,
                fleet = projection.Fleet is null
                    ? null
                    : new
                    {
                        sourceRef = projection.Fleet.SourceRef,
                        sid = projection.Fleet.Sid,
                        name = projection.Fleet.Name,
                        logoUrl = projection.Fleet.LogoUrl,
                        officialRankName = projection.Fleet.OfficialRankName,
                        officialRankValue = projection.Fleet.OfficialRankValue,
                        profile = projection.Fleet.Profile
                    },
                freshness = projection.Freshness,
                resourceVersion = projection.ResourceVersion,
                observedAtUtc = projection.ObservedAtUtc,
                profileRead = projection.ProfileRead
            });

    private static BridgeEnvelope ToOfficialFleetPublicProfileResponse(BridgeEnvelope request, AccountBridgeOfficialFleetPublicProfile value) =>
        BridgeEnvelope.Response(request, new { schemaVersion = AccountBridgeSchema.Version,
            sourceRef = value.SourceRef, sid = value.Sid, profile = value.Profile, profileRead = value.ProfileRead });

    private static BridgeEnvelope ToIdentityResponse(
        BridgeEnvelope request,
        AccountBridgeIdentityProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                state = projection.State,
                authoritativeHandle = projection.AuthoritativeHandle,
                sensitiveWritesAllowed = projection.SensitiveWritesAllowed,
                detectedHandle = projection.DetectedHandle,
                scmBindingState = projection.ScmBindingState
            });

    private static BridgeEnvelope ToCompatibilityResponse(
        BridgeEnvelope request,
        AccountBridgeCompatibilityProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                identityState = projection.IdentityState,
                relayState = projection.RelayState,
                storedLegacyCredentialAvailable = projection.StoredLegacyCredentialAvailable,
                legacyFeaturesAvailable = projection.LegacyFeaturesAvailable,
                availableActions = projection.AvailableActions
            });

    private BridgeAccountContext RequireCurrentContext(BridgeEnvelope request)
    {
        var supplied = request.AccountContext;
        var current = _host.CurrentContext;
        if (supplied is not { IsComplete: true } ||
            current is null ||
            !supplied.Environment.Equals(current.Environment, StringComparison.OrdinalIgnoreCase) ||
            !supplied.Authority.Equals(current.Authority, StringComparison.OrdinalIgnoreCase) ||
            !supplied.Subject.Equals(current.Subject, StringComparison.Ordinal))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.AccountContextRequired,
                "Account context does not match the active account.");
        }

        return current;
    }

    private static void RequireSchemaVersion(JsonElement payload, int expected = AccountBridgeSchema.Version)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("schemaVersion", out var version) ||
            version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var value) ||
            value != expected)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Account payload schema is unsupported.");
        }
    }

    private static AccountBridgePreferencePatch ParsePatch(JsonElement payload)
    {
        if (!payload.TryGetProperty("patch", out var patch) ||
            patch.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Profile patch body is required.");
        }

        var result = new AccountBridgePreferencePatch(
            ReadPatchField(patch, "locale"),
            ReadPatchField(patch, "timeZone"));
        if (result.IsEmpty)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Profile patch must contain a supported field.");
        }

        foreach (var property in patch.EnumerateObject())
        {
            if (property.Name is not ("locale" or "timeZone"))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "Profile patch contains an unsupported field.");
            }
        }

        return result;
    }

    private static PersonalProfilePresentationUpdateContract ParsePersonalProfileUpdate(
        JsonElement payload)
    {
        RejectUnknownProperties(payload, "schemaVersion", "patch");
        if (!payload.TryGetProperty("patch", out var patch) ||
            patch.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Personal profile patch body is required.");
        }

        RejectUnknownProperties(
            patch,
            "expectedRevision",
            "visibility",
            "callSign",
            "avatarStyle",
            "wallpaperId",
            "introduction",
            "modules");
        if (!patch.TryGetProperty("expectedRevision", out var revisionElement) ||
            revisionElement.ValueKind != JsonValueKind.Number ||
            !revisionElement.TryGetInt64(out var expectedRevision) ||
            expectedRevision < 0)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "expectedRevision must be a non-negative integer.");
        }

        var visibility = ReadRequiredBoundedString(patch, "visibility", 32);
        if (visibility is not ("public" or "friendsAndMainFleet" or "friendsOnly" or "private"))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "visibility is unsupported.");
        }

        if (!patch.TryGetProperty("avatarStyle", out var avatarStyleElement) ||
            avatarStyleElement.ValueKind != JsonValueKind.Number ||
            !avatarStyleElement.TryGetInt32(out var avatarStyle) ||
            avatarStyle is < 0 or > 3)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "avatarStyle must be between 0 and 3.");
        }

        if (!patch.TryGetProperty("modules", out var modulesElement) ||
            modulesElement.ValueKind != JsonValueKind.Array ||
            modulesElement.GetArrayLength() > PersonalProfileContractPolicy.MaximumModules)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "modules must be a bounded array.");
        }

        var modules = new List<PersonalProfileModuleContract>();
        foreach (var module in modulesElement.EnumerateArray())
        {
            if (module.ValueKind != JsonValueKind.Object)
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "modules must contain objects.");
            }
            RejectUnknownProperties(module, "id", "span", "isVisible", "position");
            if (!module.TryGetProperty("span", out var spanElement) ||
                !spanElement.TryGetInt32(out var span) ||
                !module.TryGetProperty("position", out var positionElement) ||
                !positionElement.TryGetInt32(out var position) ||
                !module.TryGetProperty("isVisible", out var visibleElement) ||
                visibleElement.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "module layout is invalid.");
            }
            modules.Add(new PersonalProfileModuleContract(
                ReadRequiredBoundedString(module, "id", 64),
                span,
                visibleElement.GetBoolean(),
                modules.Count,
                position));
        }

        return new PersonalProfilePresentationUpdateContract(
            expectedRevision,
            visibility,
            ReadRequiredBoundedString(patch, "callSign", 32),
            avatarStyle,
            ReadRequiredBoundedString(patch, "wallpaperId", 80),
            ReadBoundedString(patch, "introduction", PersonalProfileContractPolicy.MaximumIntroductionLength),
            modules.ToArray());
    }

    private static AccountBridgeLegacyCredential? ParseLegacyCredential(JsonElement payload)
    {
        RejectUnknownProperties(payload, "schemaVersion", "credential");
        if (!payload.TryGetProperty("credential", out var credential) ||
            credential.ValueKind == JsonValueKind.Null)
        {
            return null;
        }

        if (credential.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Legacy credential must be an object or null.");
        }

        RejectUnknownProperties(credential, "accountName", "password");
        var accountName = ReadRequiredBoundedString(credential, "accountName", 320);
        var password = ReadRequiredBoundedString(credential, "password", 1024, trim: false);
        return new AccountBridgeLegacyCredential(accountName, password);
    }

    private static string ReadRequiredBoundedString(
        JsonElement source,
        string name,
        int maximumLength,
        bool trim = true)
    {
        if (!source.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.String)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a string.");
        }

        var result = value.GetString() ?? string.Empty;
        if (trim)
        {
            result = result.Trim();
        }

        if (string.IsNullOrWhiteSpace(result) || result.Length > maximumLength)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} has an invalid length.");
        }

        return result;
    }

    private static string ReadBoundedString(
        JsonElement source,
        string name,
        int maximumLength)
    {
        if (!source.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a string.");
        }

        var result = (value.GetString() ?? string.Empty).Trim();
        if (result.Length > maximumLength)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} has an invalid length.");
        }
        return result;
    }

    private static void RejectUnknownProperties(
        JsonElement source,
        params string[] allowedNames)
    {
        var allowed = allowedNames.ToHashSet(StringComparer.Ordinal);
        foreach (var property in source.EnumerateObject())
        {
            if (!allowed.Contains(property.Name))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "Account payload contains an unsupported field.");
            }
        }
    }

    private static AccountBridgePatchField ReadPatchField(JsonElement patch, string name)
    {
        if (!patch.TryGetProperty(name, out var value))
        {
            return AccountBridgePatchField.Unspecified;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Null => AccountBridgePatchField.Set(null),
            JsonValueKind.String => AccountBridgePatchField.Set(value.GetString()),
            _ => throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Profile patch fields must be strings or null.")
        };
    }

    private void OnAccountChanged(long generation)
    {
        lock (_activityGate)
            foreach (var active in _activityCancellations.Values)
                if (active.Generation != generation) active.Source.Cancel();
        BridgeEnvelope envelope;
        Action<BridgeEnvelope>? publish = null;
        lock (_eventGate)
        {
            envelope = BridgeEnvelope.Event(
                "account.changed",
                generation,
                ++_eventSequence,
                new { schemaVersion = AccountBridgeSchema.Version });
            if (_activeDispatches > 0)
            {
                _pendingEvents.Add(envelope);
            }
            else
            {
                publish = EventReady;
            }
        }

        publish?.Invoke(envelope);
    }

    private void BeginDispatchEventCollection()
    {
        lock (_eventGate)
        {
            if (_activeDispatches++ == 0) _pendingEvents.Clear();
        }
    }

#if STARBRIDGE_SESSION_PROBE || STARBRIDGE_MEMBER_READ_PROBE
    private static int MemberReadProbeSchema(string name, JsonElement payload) =>
        name is (AccountBridgeRequestNames.GetOfficialFleetMembers or AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers) &&
        payload.ValueKind == JsonValueKind.Object && payload.TryGetProperty("schemaVersion", out var schema) &&
        schema.ValueKind == JsonValueKind.Number && schema.TryGetInt32(out var version) && version is 1 or 2 ? version : 0;
#endif

    private AccountBridgeDispatchResult Result(BridgeEnvelope response)
    {
        AccountReadTiming.Response(response.Name, response.Status, response.Error?.Code);
        lock (_eventGate)
        {
            // No reader may clear another reader's buffered invalidations.
            // Flush the ordered batch with the final response, preserving the
            // existing response-before-account.changed transport contract.
            if (--_activeDispatches > 0) return new AccountBridgeDispatchResult(response, []);
            var events = _pendingEvents.ToArray();
            _pendingEvents.Clear();
            return new AccountBridgeDispatchResult(response, events);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        lock (_activityGate)
            foreach (var active in _activityCancellations.Values) active.Source.Cancel();
        _host.AccountChanged -= OnAccountChanged;
        if (_host is ScmAccountBridgeHost scm) scm.GameIdentityChanged -= OnGameIdentityChanged;
        _dispatchGate.Dispose();
    }
}
