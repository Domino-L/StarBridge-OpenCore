namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    internal bool HasLocalIdentityForOnlineSelection => CaptureLocalIdentity() is not null;
    // Captured from the startup reader; never inferred from later device writes.
    internal bool ReturningAtStartup { get; set; }
    internal bool AllowsOnlineSelection => store.SetupCompleted || ReturningAtStartup || HasLocalIdentityForOnlineSelection;
    // In-memory fence for a scan bracketed by full durable LocalMode checks.
    // Reads no file and is never an authorization by itself.
    internal Func<bool> CaptureLocalModeFence()
    {
        var epoch = Interlocked.Read(ref _epoch);
        var accepted = Volatile.Read(ref _accepted);
        return () => !_closed && !_changing && accepted is not null && Volatile.Read(ref _accepted) == accepted &&
            Interlocked.Read(ref _epoch) == epoch;
    }
    internal long ModeStoreReads => store.Reads;
    internal sealed record GuideScope(string ProfileId, long Generation, long ModeRevision);

    // The same confirmed profile used by completion and installed identity binding.
    // Never restores an account or requests fresh partner identity facts.
    internal GuideScope? CaptureGuideScope()
    {
        try
        {
            if (_closed || _changing) return null;
            var generation = ControlGeneration;
            var selected = Current;
            if (selected.ActiveMode == "local" ? !LocalMode().Active :
                selected.ActiveMode != "online" || !HasInstalledOnlineForCompletion) return null;
            var local = CaptureLocalIdentity();
            return local is not null && generation == ControlGeneration && selected == Current
                ? new(local.Profile.Id, generation, selected.Revision) : null;
        }
        catch (LocalFirstUseException) { return null; }
    }
}
