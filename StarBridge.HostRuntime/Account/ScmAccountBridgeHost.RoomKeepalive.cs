using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly object _roomKeepaliveGate = new();
    private bool _roomKeepaliveEnabled;
    private CancellationTokenSource? _roomKeepaliveCancellation;
    private TimeSpan _roomKeepaliveInterval = TimeSpan.FromSeconds(30);
    internal Task RoomKeepaliveCompletion { get; private set; } = Task.CompletedTask;
    private Task _roomKeepaliveStopCompletion = Task.CompletedTask;
    private sealed record RoomRenewalScope(BridgeAccountContext Owner, long Generation);
    private RoomRenewalScope? _roomRenewal;

    internal bool HasRoomPublication(BridgeAccountContext owner, long generation) =>
        IsCurrentRoomKeepalive(owner, generation) &&
        (Volatile.Read(ref _roomRenewal) is { } renewal && renewal.Owner == owner && renewal.Generation == generation ||
            _roomOverlay.HasConfirmedMembership(owner, generation));

    // Enabled by production composition, independent of Flutter/overlay visibility.
    // Tests can supply a short interval without changing the production cadence.
    internal void EnableRoomMembershipKeepalive(TimeSpan? interval = null)
    {
        lock (_roomKeepaliveGate)
        {
            if (interval is { } value)
            {
                if (value <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(interval));
                _roomKeepaliveInterval = value;
            }
            _roomKeepaliveEnabled = true;
            EnsureRoomMembershipKeepalive();
        }
    }

    private void StopRoomMembershipKeepalive()
    {
        lock (_roomKeepaliveGate)
        {
            if (_roomKeepaliveCancellation is not null)
                _roomKeepaliveStopCompletion = Task.WhenAll(_roomKeepaliveStopCompletion, RoomKeepaliveCompletion);
            _roomKeepaliveCancellation?.Cancel();
            _roomKeepaliveCancellation = null;
        }
    }

    private void EnsureRoomMembershipKeepalive()
    {
        lock (_roomKeepaliveGate)
        {
            if (IsBusinessStartupDeferred || !_roomKeepaliveEnabled || _disposed || _localModeSessionLoopsStopped || _partyRooms is null || _session is null ||
                GameplayTimeContext is not { } owner || _roomKeepaliveCancellation is not null) return;
            var generation = Generation;
            var cancellation = new CancellationTokenSource();
            _roomKeepaliveCancellation = cancellation;
            RoomKeepaliveCompletion = Task.Run(async () =>
            {
                var token = cancellation.Token;
                try
                {
                    while (!token.IsCancellationRequested && IsCurrentRoomKeepalive(owner, generation))
                    {
                        var interval = _roomKeepaliveInterval;
                        try { await RenewRoomMembershipAsync(owner, generation, token).ConfigureAwait(false); }
                        catch (OperationCanceledException) when (token.IsCancellationRequested) { break; }
                        catch (Exception error) when (error is AccountBridgeHostException or BridgeStaleGenerationException or
                            OperationCanceledException or HttpRequestException or IOException or ObjectDisposedException or TimeoutException)
                        {
                            // No cached successful heartbeat, auth fallback or business write replay.
                            interval = TimeSpan.FromTicks(Math.Min(interval.Ticks * 2, TimeSpan.FromSeconds(60).Ticks));
                        }
                        await Task.Delay(interval, token).ConfigureAwait(false);
                    }
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { }
                finally
                {
                    lock (_roomKeepaliveGate)
                    {
                        if (ReferenceEquals(_roomKeepaliveCancellation, cancellation))
                            _roomKeepaliveCancellation = null;
                        cancellation.Dispose();
                    }
                }
            });
        }
    }

    private bool IsCurrentRoomKeepalive(BridgeAccountContext owner, long generation) =>
        !_disposed && Generation == generation && GameplayTimeContext == owner && _session is not null;

    private async Task RenewRoomMembershipAsync(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        await _roomSessionGate.WaitAsync(token).ConfigureAwait(false);
        RoomRenewalScope? renewal = null;
        try
        {
            if (!IsCurrentRoomKeepalive(owner, generation) || RoomPublicationSuspended(owner, generation)) return;
            // Reconfirm membership before every lease. Reads alone do not renew anything.
            var directory = await GetPartyRoomsCoreAsync(owner, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (!IsCurrentRoomKeepalive(owner, generation)) return;
            _roomOverlay.ApplyDirectory(owner, generation, ProjectRoomOverlayIdentity(directory, owner), OverlayLocalHandle());
            if (!directory.SupportsMembershipKeepalive || directory.CurrentRoomId is null) return;
            var session = RequireRelaySession(owner);
            // An idle directory loop is not a renewal. Track only the interval
            // with authenticated membership, including the admission wait/send.
            renewal = new(owner, generation);
            Volatile.Write(ref _roomRenewal, renewal);
            var result = await SendRelayRequestAsync(session,
                async (active, ct) => {
                    using var positiveLease = _sharedPublicationAdmission is { } positiveAdmission
                        ? await positiveAdmission.EnterAsync(ct).ConfigureAwait(false) : null;
                    if (!IsCurrentRoomKeepalive(owner, generation) || RoomPublicationSuspended(owner, generation))
                        throw new OperationCanceledException("Room presence renewal is paused.", ct);
                    return await _partyRooms!.KeepaliveAsync(active.AccessToken, directory, ct).ConfigureAwait(false);
                }, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            lock (_realtimeGate)
            {
                if (!IsCurrentRoomKeepalive(owner, generation)) return;
                RequireSameRelaySession(RequireRelaySession(owner), result.ActiveSession);
                _session = result.ActiveSession.Scm;
                if (!result.Result) _roomOverlay.Clear();
            }
        }
        catch (AccountBridgeHostException error)
        {
            if (IsCurrentRoomKeepalive(owner, generation) && !error.Retryable) _roomOverlay.Clear();
            throw;
        }
        finally
        {
            if (renewal is not null) Interlocked.CompareExchange(ref _roomRenewal, null, renewal);
            _roomSessionGate.Release();
        }
    }
}
