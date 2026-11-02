using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

// One consent store and admission fence, two independent delivery state machines.
// A failure/compensating clear/backoff belongs only to the lane that produced it.
internal sealed class PrivacyPublicationPair : IDisposable
{
    private readonly PrivacyPublication _ordinary, _official;
    private readonly SemaphoreSlim _visibilityGate = new(1, 1);
    private bool? _resumeForTransition;
    internal PrivacyPublicationPair(LocalPrivacyStore store, Func<PrivacyPublicationInput?> current,
        Func<PrivacyPublicationInput, JsonElement, CancellationToken, Task> send, bool startTimer = true,
        Func<PlayerPresenceVisibilityMode>? visibility = null, TimeProvider? timeProvider = null,
        Action<BridgeAccountContext, long>? confirmExplicitSharing = null,
        Func<PublicationVisibilitySnapshot>? visibilitySnapshot = null,
        Func<BridgeAccountContext, long, bool>? consumeExplicitOnlineResume = null,
        Func<PrivacyPublicationInput?>? currentOwner = null,
        Func<BridgeAccountContext, long, bool>? roomPublicationActive = null)
    {
        PrivacyPublication Create(PrivacyPublicationLane lane) => new(store, current, send, startTimer,
            visibility, timeProvider, confirmExplicitSharing, visibilitySnapshot,
            (owner, generation) => _resumeForTransition ??= consumeExplicitOnlineResume?.Invoke(owner, generation) == true,
            currentOwner, roomPublicationActive, lane);
        _ordinary = Create(PrivacyPublicationLane.Ordinary);
        _official = Create(PrivacyPublicationLane.Official);
        _ordinary.StatusChanged += Changed; _official.StatusChanged += Changed;
    }
    internal event Action? StatusChanged;
    internal Action<string, string?>? Diagnostic { get; set; }
    private void Changed() { var s = Status; Diagnostic?.Invoke(s.State, s.ErrorCode); StatusChanged?.Invoke(); }
    internal PrivacyPublicationStatus OrdinaryStatus => _ordinary.Status;
    internal PrivacyPublicationStatus OfficialStatus => _official.Status;
    internal PrivacyPublicationStatus Status => Combine(_ordinary.Status, _official.Status);
    private static PrivacyPublicationStatus Combine(PrivacyPublicationStatus a, PrivacyPublicationStatus b)
    {
        // Never report global success when either configured lane is still failing.
        if (a.ErrorCode is not null) return a;
        if (b.ErrorCode is not null) return b;
        if (a.State == "inactive") return b;
        if (b.State == "inactive") return a;
        if (a.State == "publishing" || b.State == "publishing") return new("publishing");
        if (a.State != "applied" && a.State != "withdrawn") return a;
        if (b.State != "applied" && b.State != "withdrawn") return b;
        return a;
    }
    internal PrivacyPublicationStatus StatusFor(BridgeAccountContext owner) => Combine(_ordinary.StatusFor(owner), _official.StatusFor(owner));
    internal bool StartDeferredWork() { var a = _ordinary.StartDeferredWork(); var b = _official.StartDeferredWork(); return a && b; }
    internal void Invalidate() { _ordinary.Invalidate(); _official.Invalidate(); }
    internal Task TickAsync() => Task.WhenAll(_ordinary.TickAsync(), _official.TickAsync());
    internal async Task<PrivacyPublicationStatus> ApplyAsync(BridgeAccountContext owner, long generation, long revision,
        CancellationToken token, bool preservePause = false)
    {
        await Task.WhenAll(_ordinary.ApplyAsync(owner, generation, revision, token, preservePause),
            _official.ApplyAsync(owner, generation, revision, token, preservePause)).ConfigureAwait(false);
        return Status;
    }
    internal async Task<bool> StopAsync(CancellationToken token, bool explicitRequest = false)
    {
        var results = await Task.WhenAll(_ordinary.StopAsync(token, explicitRequest), _official.StopAsync(token, explicitRequest)).ConfigureAwait(false);
        return results.All(v => v);
    }
    internal async Task<bool> ChangeVisibilityAsync(BridgeAccountContext owner, long generation,
        Func<CancellationToken, Task> change, CancellationToken token)
    {
        await _visibilityGate.WaitAsync(token).ConfigureAwait(false);
        try {
            _resumeForTransition = null;
            // Consume the one explicit resume observation once for this same
            // owner/transition; both lanes must see it, never a later transition.
            var first = await _ordinary.PrepareVisibilityAsync(owner, generation, change, token).ConfigureAwait(false);
            var second = await _official.PrepareVisibilityAsync(owner, generation, _ => Task.CompletedTask, token).ConfigureAwait(false);
            await TickAsync().ConfigureAwait(false);
            bool Acknowledged(PrivacyPublicationStatus s) => s.State is "applied" or "withdrawn" or "inactive" || s.State == "identityRequired" && s.AppliedAt is not null;
            return first && second && Acknowledged(_ordinary.Status) && Acknowledged(_official.Status);
        }
        catch {
            // A failed authority change is uncertain for both lanes. Their
            // snapshots fail closed; no old positive payload is replayed.
            await Task.WhenAll(_ordinary.TickAsync(), _official.TickAsync()).ConfigureAwait(false);
            throw;
        }
        finally { _resumeForTransition = null; _visibilityGate.Release(); }
    }
    internal void ObserveVisibility(PublicationVisibilitySnapshot snapshot, bool wakePublication = false)
    { _ordinary.ObserveVisibility(snapshot, wakePublication); _official.ObserveVisibility(snapshot, wakePublication); }
    internal bool IsPositivePublicationAllowed(BridgeAccountContext owner, long generation) =>
        _ordinary.IsPositivePublicationAllowed(owner, generation) && _official.IsPositivePublicationAllowed(owner, generation);
    internal bool IsPublicationSuspended(BridgeAccountContext owner, long generation) =>
        _ordinary.IsPublicationSuspended(owner, generation) || _official.IsPublicationSuspended(owner, generation);
    internal void RequireNoObservedPause(PrivacyPublicationInput input)
    { _ordinary.RequireNoObservedPause(input); _official.RequireNoObservedPause(input); }
    internal Task RetireAsync() => Task.WhenAll(_ordinary.RetireAsync(), _official.RetireAsync());
    public void Dispose() { _ordinary.Dispose(); _official.Dispose(); }
}

internal enum PrivacyPublicationLane { Combined, Ordinary, Official }


