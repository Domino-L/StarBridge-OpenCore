using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Native retains this read-only selection, not an individual device runtime.
// The root still owns draining/replacement; absence is not an account fallback.
internal sealed class LocalOverlaySourceBinding(Func<LocalOverlaySourceRuntime?> current) : IInformationOverlayLocalSource
{
    public InformationOverlayLocalSourceFrame? Capture()
    {
        try
        {
            var owner = current();
            if (owner is null) return InformationOverlayLocalSourceFrame.Unavailable;
            var frame = owner.Capture();
            bool Current() => ReferenceEquals(owner, current());
            if (!Current()) return InformationOverlayLocalSourceFrame.Unavailable;
            // Null is allowed only when that same owner confirmed non-local mode.
            return frame?.RestrictTo(Current);
        }
        catch { return InformationOverlayLocalSourceFrame.Unavailable; }
    }
}

// Read-only adapter for the actual confirmed local log slot. No timer, process
// probe, settings write, account callback, remote reader or completion receipt.
internal sealed class LocalOverlaySourceRuntime(LocalFirstUseStore identities, LocalGameLogRuntime game,
    Func<(bool Active, long Generation)> localMode, TimeProvider? time = null) : IInformationOverlayLocalSource
{
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private readonly AsyncWorkRetirement _work = new();
    private readonly object _gate = new();
    private sealed record Scope(long Generation, LocalFirstUseSource Source, LocalDeviceProfile Profile);
    private Scope? _scope;
    private string _key = Guid.NewGuid().ToString("N");
    public InformationOverlayLocalSourceFrame? Capture()
    {
        using var work = _work.Enter(default);
        if (work is null) return InformationOverlayLocalSourceFrame.Unavailable;
        try
        {
            var mode = localMode();
            if (!mode.Active && mode.Generation >= 0)
            {
                Clear();
                return localMode() == mode && !_work.IsClosed ? null : InformationOverlayLocalSourceFrame.Unavailable;
            }
            if (!mode.Active || mode.Generation < 0) { Clear(); return InformationOverlayLocalSourceFrame.Unavailable; }
            var scope = From(identities.Read(), mode.Generation);
            if (scope is null) { Clear(); return InformationOverlayLocalSourceFrame.Unavailable; }
            string key;
            lock (_gate)
            {
                if (_scope != scope) { _scope = scope; _key = Guid.NewGuid().ToString("N"); }
                key = _key;
            }
            var view = game.Current;
            bool Current()
            {
                using var displayRead = _work.Enter(default);
                return displayRead is not null && CurrentScope(scope, key) && game.Current == view && CurrentScope(scope, key);
            }
            if (!Current()) return InformationOverlayLocalSourceFrame.Unavailable;
            var valid = view.SourceKey == scope.Source.SourceKey && view.Version == scope.Source.Version &&
                view.ListeningEnabled == true && view.ObservedAt is { } at && _time.GetUtcNow() >= at &&
                _time.GetUtcNow() - at <= TimeSpan.FromSeconds(10);
            var ready = valid && view.State == "ready" && scope.Profile.Handle.Equals(view.Handle, StringComparison.OrdinalIgnoreCase);
            var stopped = valid && view.State == "notRunning";
            var observation = new InformationOverlayLocalObservation(ready ? "ready" : stopped ? "notRunning" : "waiting",
                ready || stopped ? scope.Profile.Handle : null, ready ? view.LocalSession : GameLogSessionSnapshot.Empty);
            return new(key, scope.Generation, observation, Current, _time.GetUtcNow);
        }
        catch { Clear(); return InformationOverlayLocalSourceFrame.Unavailable; }
    }
    private bool CurrentScope(Scope scope, string key)
    {
        try
        {
            if (_work.IsClosed || localMode() != (true, scope.Generation) || From(identities.Read(), scope.Generation) != scope) return false;
            lock (_gate) if (_scope != scope || _key != key) return false;
            return localMode() == (true, scope.Generation) && !_work.IsClosed;
        }
        catch { return false; }
    }
    private static Scope? From(LocalFirstUseSnapshot value, long generation)
    {
        var source = value.Sources.SingleOrDefault(s => s.SourceKey == value.SelectedSourceKey);
        var profile = value.Profiles.SingleOrDefault(p => p.Id == source?.ConfirmedProfileId);
        return source is not null && profile is not null && !source.NeedsFreshGameEvidence && value.ActiveProfileId == profile.Id
            ? new(generation, source, profile) : null;
    }
    private void Clear() { lock (_gate) { _scope = null; _key = Guid.NewGuid().ToString("N"); } }
    internal async Task RetireAsync() { await _work.Close().ConfigureAwait(false); Clear(); }
}
