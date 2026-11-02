namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
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
