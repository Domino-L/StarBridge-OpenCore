using StarBridge.HostRuntime.Onboarding;

namespace StarBridge.HostRuntime;

public sealed partial class NativeAccountRuntimeBinding
{
    private OnlineInstallationAttempt? _onlineInstallation;

    // Native composition only, not onboarding completion.
    // The supplied composition belongs to this original attempt. An observer may
    // leave, but configuration, installation and recovery must physically exit.
    internal Task<FirstUseModeObservation> InstallConfirmedOnlineAsync(long revision,
        Action<AccountBridgeRuntime> configure, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(configure);
        token.ThrowIfCancellationRequested();
        var mode = _root.FirstUseMode ?? throw new LocalFirstUseException("firstUse.mode_receipt_required");
        OnlineInstallationAttempt? pending;
        lock (_gate) pending = _onlineInstallation;
        if (pending is { Completion.Task.IsCompleted: false })
        {
            if (pending.Revision != revision || !ReferenceEquals(pending.Configure, configure))
                throw new LocalFirstUseException("firstUse.operation_in_progress");
            return pending.Completion.Task.WaitAsync(token);
        }
        // A completed attempt cannot be replayed as a new permission. This live
        // identity precondition does not itself replace any receipt below.
        var origin = FirstUseModeRuntime.InstallationOrigin.Capture(mode, revision);
        if (revision < 0 || origin is null)
            throw new LocalFirstUseException("firstUse.context_changed");
        OnlineInstallationAttempt attempt;
        lock (_gate)
        {
            if (_disposed || !ReferenceEquals(_onlineInstallation, pending))
                throw new LocalFirstUseException("firstUse.context_changed");
            attempt = new(revision, mode, origin, configure);
            _onlineInstallation = attempt;
        }
        _ = CompleteOnlineInstallationAsync(attempt);
        return attempt.Completion.Task.WaitAsync(token);
    }

    private sealed record OnlineInstallationAttempt(long Revision, FirstUseModeRuntime Mode,
        FirstUseModeRuntime.InstallationOrigin Origin,
        Action<AccountBridgeRuntime> Configure)
    {
        internal readonly TaskCompletionSource<FirstUseModeObservation> Completion =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal OnlineInstallationFailure? Failure;
    }

    // Finite, non-authoritative diagnostics. Never include exception messages,
    // account IDs, paths, request bodies or credentials in this observation.
    internal sealed record OnlineInstallationFailure(string Stage, string Kind);
    internal sealed record OnlineInstallationObservation(string Phase, long Revision,
        FirstUseModeObservation Mode, long ControlGeneration, OnlineInstallationFailure? Failure = null);

    // Poll the original physical task, not a renderer-supplied installation
    // receipt or a mode projection. A cancelled observer can rejoin this task.
    internal OnlineInstallationObservation ObserveOnlineInstallation(long revision)
    {
        OnlineInstallationAttempt? attempt;
        lock (_gate)
        {
            if (_disposed) throw new LocalFirstUseException("firstUse.context_changed");
            attempt = _onlineInstallation;
        }
        var mode = _root.FirstUseMode ?? throw new LocalFirstUseException("firstUse.mode_receipt_required");
        var observed = mode.Current;
        var generation = mode.ControlGeneration;
        var phase = "idle";
        if (attempt is not null && attempt.Revision == revision)
        {
            phase = attempt.Completion.Task.IsCompletedSuccessfully ? "completed" : "running";
            if (phase == "completed")
            {
                var result = attempt.Completion.Task.Result;
                if (result.Revision != observed.Revision)
                    throw new LocalFirstUseException("firstUse.context_changed");
                if (result.State != "recoveryRequired" && (result != observed || Generation != generation))
                    throw new LocalFirstUseException("firstUse.context_changed");
                observed = result;
            }
        }
        else if (revision != observed.Revision || attempt is { Completion.Task.IsCompleted: false })
            throw new LocalFirstUseException("firstUse.context_changed");
        lock (_gate)
        {
            if (_disposed || !ReferenceEquals(_onlineInstallation, attempt))
                throw new LocalFirstUseException("firstUse.context_changed");
        }
        if (generation < 0 || mode.ControlGeneration != generation ||
            observed.State != "recoveryRequired" && mode.Current != observed)
            throw new LocalFirstUseException("firstUse.context_changed");
        return new(phase, revision, observed, generation,
            phase == "completed" ? attempt?.Failure : null);
    }

    internal FirstUseOnlineInstallationBridgeDispatcher? CreateOnlineInstallationDispatcher(
        AccountBridgeRuntime.NativeBusinessComposition composition) => _root.FirstUseMode is { } mode
        ? new(mode, this, composition.Configure) : null;

    private bool OwnsInstallationAttempt(OnlineInstallationAttempt attempt)
    {
        lock (_gate) return !_disposed && ReferenceEquals(_onlineInstallation, attempt);
    }

    private async Task CompleteOnlineInstallationAsync(OnlineInstallationAttempt attempt)
    {
        await Task.Yield(); // Reserve before any IO, cancellation or user callback.
        AccountBridgeRuntime.PreparedFirstUseBusinessOwner? prepared = null;
        Task? sources = null;
        var nativeDrainStarted = false;
        var stage = "prepareAccount";
        FirstUseModeObservation result;
        try
        {
            prepared = await attempt.Mode.PrepareOnlineBusinessOwnerAsync(attempt.Revision).ConfigureAwait(false);
            if (prepared is null || !OwnsInstallationAttempt(attempt) || !prepared.IsCurrent)
                throw new LocalFirstUseException("firstUse.context_changed");
            nativeDrainStarted = true;
            stage = "drainNative";
            var callbacks = await PrepareHandoffAsync(prepared).ConfigureAwait(false);
            if (callbacks is null || !OwnsInstallationAttempt(attempt) || !prepared.IsCurrent)
                throw new LocalFirstUseException("firstUse.context_changed");
            stage = "retireLocalSources";
            sources = _root.RetireFirstUseLocalSourcesAsync();
            await sources.ConfigureAwait(false);
            if (!OwnsInstallationAttempt(attempt) || !prepared.IsCurrent)
                throw new LocalFirstUseException("firstUse.context_changed");
            stage = "stageBusiness";
            var installation = prepared.StageInstallation(callbacks, sources);
            if (installation is null)
                throw new LocalFirstUseException("firstUse.mode_receipt_required");
            stage = "configureBusiness";
            if (!installation.Configure(attempt.Configure))
                throw new LocalFirstUseException("firstUse.mode_receipt_required");
            stage = "activateBusiness";
            if (!installation.TryActivate())
                throw new LocalFirstUseException("firstUse.mode_receipt_required");
            stage = "installNative";
            if (!OwnsInstallationAttempt(attempt) || InstallBusiness(installation) is not { IsCurrent: true })
                throw new LocalFirstUseException("firstUse.mode_receipt_required");
            stage = "commitMode";
            result = await attempt.Mode.CommitOnlineAsync(attempt.Revision, Guid.NewGuid().ToString("N"), installation)
                .ConfigureAwait(false);
            if (result.State != "online") attempt.Failure = new(stage, "notCommitted");
        }
        catch (Exception error)
        {
            attempt.Failure = new(stage, error switch {
                OperationCanceledException => "cancelled",
                LocalFirstUseException => "rejected",
                IOException or UnauthorizedAccessException => "storage",
                TimeoutException => "timeout",
                _ => "unexpected"
            });
            result = await RecoverOnlineInstallationAsync(attempt, prepared, sources, nativeDrainStarted).ConfigureAwait(false);
        }
        attempt.Completion.TrySetResult(result);
    }

    private async Task<FirstUseModeObservation> RecoverOnlineInstallationAsync(OnlineInstallationAttempt attempt,
        AccountBridgeRuntime.PreparedFirstUseBusinessOwner? prepared, Task? sources, bool nativeDrainStarted)
    {
        FirstUseModeObservation Recovery() => new("recoveryRequired", attempt.Mode.Current.Revision);
        try
        {
            // Never cancel a newer intent or classify an external write as ours.
            if (!OwnsInstallationAttempt(attempt)) return Recovery();
            var returned = attempt.Origin.ReturnedLocal(prepared);
            if (returned is null)
            {
                if (attempt.Mode.Current.Revision != attempt.Revision) return Recovery();
                returned = await attempt.Mode.CancelOnlineAsync(attempt.Revision, Guid.NewGuid().ToString("N"))
                    .ConfigureAwait(false);
            }
            if (returned.State is not ("local" or "offline") || !OwnsInstallationAttempt(attempt)) return Recovery();
            if (attempt.Origin.ReturnedLocal(prepared) != returned) return Recovery();
            if (!nativeDrainStarted || prepared is null) return returned;
            var local = attempt.Mode.LocalMode();
            if (!local.Active) return Recovery();
            // A staged installation's original cancellation already rebuilds
            // both graphs. Before staging, consume the same held Native drain
            // and source exit ourselves; no successful task may be substituted.
            if (_root.HasCurrentFirstUseLocalSources(local.Generation) &&
                Read(owner => ReferenceEquals(owner, _root), false)) return returned;
            sources ??= _root.RetireFirstUseLocalSourcesAsync();
            await sources.ConfigureAwait(false);
            if (!OwnsInstallationAttempt(attempt) ||
                !await _root.RestoreFirstUseLocalSourcesAsync(sources, local.Generation).ConfigureAwait(false) ||
                !await RestoreLocalCallbacksAsync(prepared, local.Generation).ConfigureAwait(false) ||
                !OwnsInstallationAttempt(attempt) || attempt.Origin.ReturnedLocal(prepared) != returned) return Recovery();
            return returned;
        }
        catch { return Recovery(); }
    }
}
