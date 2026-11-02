using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record FirstUseCompletionObservation(string State, string? CompletionKey = null,
    string? Mode = null, string? CompletedMode = null);

// The Host rereads the existing domain owners. Navigation and renderer booleans
// cannot issue this receipt, install an account or change any consent.
internal sealed class FirstUseCompletionRuntime(string root, FirstUseModeRuntime mode,
    LocalDeviceSetupReviewRuntime review)
{
    private readonly LocalFirstUseStore _local = new(root);
    private readonly LocalGameplayTimeStore _statistics = new(root);
    private readonly FirstUseCompletionStore _store = new(root);
    private readonly AsyncWorkRetirement _work = new();
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile bool _closed;
    private Issued? _issued;
    private sealed record Scope(long Generation, FirstUseModeObservation Mode, LocalFirstUseSnapshot Local,
        LocalFirstUseSource Source, LocalDeviceProfile Profile, LocalDeviceSetupChoices Choices,
        GameplayRecordingConsent StatisticsConsent, FirstUseCompletion? Previous, string Fingerprint);
    private sealed record Issued(string Key, Scope Scope);

    internal async Task<FirstUseCompletionObservation> ReadAsync(CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) return new("unavailable");
        await _gate.WaitAsync(work.Token).ConfigureAwait(false);
        try { return await ReadCore(work.Token).ConfigureAwait(false); }
        finally { _gate.Release(); }
    }

    private async Task<FirstUseCompletionObservation> ReadCore(CancellationToken token)
    {
        _issued = null;
        var (state, scope) = await Capture(token).ConfigureAwait(false);
        if (scope is null) return new(state, CompletedMode: _store.Read()?.Mode);
        if (scope.Previous is { } completed && completed.Mode == scope.Mode.ActiveMode &&
            completed.ProfileId == scope.Profile.Id && completed.SourceKey == scope.Source.SourceKey)
            return new("completed", Mode: completed.Mode, CompletedMode: completed.Mode);
        _issued = new(Guid.NewGuid().ToString("N"), scope);
        return new("ready", _issued.Key, scope.Mode.ActiveMode, scope.Previous?.Mode);
    }

    internal async Task<FirstUseCompletionObservation> FinishAsync(string completionKey, CancellationToken token = default)
    {
        if (!LocalFirstUseValidation.Id(completionKey)) throw new LocalFirstUseException("firstUse.invalid_request");
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        if (!await _gate.WaitAsync(0, work.Token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var issued = _issued;
            _issued = null;
            if (issued is null || issued.Key != completionKey) throw new LocalFirstUseException("firstUse.context_changed");
            var (state, observed) = await Capture(work.Token).ConfigureAwait(false);
            if (state != "ready" || observed is null || observed.Fingerprint != issued.Scope.Fingerprint)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (observed.Mode.State is not ("local" or "offline" or "online"))
                throw new LocalFirstUseException("firstUse.mode_receipt_required");
            bool Current() => !_closed && !work.Token.IsCancellationRequested && FastCurrent(observed) &&
                review.CompletionChoicesCurrent(observed.Choices, work.Token);
            _store.Save(observed.Previous, Guid.NewGuid().ToString("N"), observed.Mode.ActiveMode!,
                observed.Profile.Id, observed.Source.SourceKey, Current);
            work.Token.ThrowIfCancellationRequested();
            if (_closed) throw new LocalFirstUseException("firstUse.context_changed");
            return await ReadCore(work.Token).ConfigureAwait(false);
        }
        finally { _gate.Release(); }
    }

    private async Task<(string State, Scope? Scope)> Capture(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (_closed) return ("unavailable", null);
        var generation = mode.ControlGeneration;
        var selectedMode = mode.Current;
        if (!ModeReady(selectedMode)) return ("needsMode", null);
        var local = _local.Read();
        var source = local.Sources.SingleOrDefault(s => s.SourceKey == local.SelectedSourceKey);
        var profile = local.Profiles.SingleOrDefault(p => p.Id == source?.ConfirmedProfileId);
        if (source is null || profile is null || source.NeedsFreshGameEvidence || local.ActiveProfileId != profile.Id ||
            source.ConfirmedObservedAt is null || source.ListeningEnabled is null)
            return ("needsIdentity", null);
        var device = await review.ReadAsync(token).ConfigureAwait(false);
        if (device is not { State: "reviewed", Choices: not null }) return ("needsSettings", null);
        var statistics = _statistics.Read(profile.Id);
        if (statistics.Consent == GameplayRecordingConsent.Unknown) return ("needsStatistics", null);
        var previous = _store.Read();
        var fingerprint = Hash(new { generation, mode = selectedMode, local, choices = device.Choices,
            consent = statistics.Consent, previous });
        var scope = new Scope(generation, selectedMode, local, source, profile, device.Choices, statistics.Consent, previous, fingerprint);
        token.ThrowIfCancellationRequested();
        return FastCurrent(scope) ? ("ready", scope) : ("contextChanged", null);
    }

    private bool FastCurrent(Scope scope)
    {
        try
        {
            return !_closed && mode.ControlGeneration == scope.Generation && mode.Current == scope.Mode && ModeReady(scope.Mode) &&
                Hash(_local.Read()) == Hash(scope.Local) && _statistics.Read(scope.Profile.Id).Consent == scope.StatisticsConsent;
        }
        catch { return false; }
    }

    private bool ModeReady(FirstUseModeObservation selected) => selected.ActiveMode switch
    {
        "local" => selected.PublicationSuspended && mode.LocalMode().Active,
        "online" => mode.HasInstalledOnlineForCompletion,
        _ => false
    };
    private static string Hash<T>(T value) => Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(value)));
    internal Task RetireAsync() { _closed = true; _issued = null; return _work.Close(); }
}
