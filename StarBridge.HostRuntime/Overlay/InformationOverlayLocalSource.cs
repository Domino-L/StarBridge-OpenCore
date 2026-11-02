using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>Null means a known non-local mode. An unavailable local frame still
/// suppresses account sources. This is display-only, not a mode or publication receipt.</summary>
public interface IInformationOverlayLocalSource
{
    InformationOverlayLocalSourceFrame? Capture();
}

public sealed record InformationOverlayLocalObservation(string State, string? Handle,
    GameLogSessionSnapshot Session)
{
    public static InformationOverlayLocalObservation Unavailable { get; } = new("unavailable", null, GameLogSessionSnapshot.Empty);
}

/// <summary>Host-created process-local frame; never serialized or accepted as caller authority.
/// Contains no account context, directory, remote lease or publication grant.</summary>
public sealed class InformationOverlayLocalSourceFrame
{
    private readonly string _key;
    private readonly long _generation;
    private readonly InformationOverlayLocalObservation _observation;
    private readonly Func<bool> _current;
    private readonly Func<DateTimeOffset> _now;
    internal InformationOverlayLocalSourceFrame(string key, long generation,
        InformationOverlayLocalObservation observation, Func<bool> current, Func<DateTimeOffset> now)
    { _key = key; _generation = generation; _observation = observation; _current = current; _now = now; }

    public static InformationOverlayLocalSourceFrame Unavailable { get; } = new("unavailable-local", 0,
        InformationOverlayLocalObservation.Unavailable, () => false, () => DateTimeOffset.UtcNow);
    private bool Current() { try { return _current(); } catch { return false; } }
    // Preserve the original frame's lifetime and module scope while adding the
    // root's selected-owner guard. A replacement never reuses an old frame.
    internal InformationOverlayLocalSourceFrame RestrictTo(Func<bool> ownerCurrent) =>
        new(_key, _generation, _observation, () => ownerCurrent() && Current() && ownerCurrent(), _now);
    public InformationOverlayLocalObservation Read() => Current() ? _observation : InformationOverlayLocalObservation.Unavailable;

    public InformationOverlayModuleReadResult ReadModules(InformationOverlayRuntimeWorkspace workspace)
    {
        ArgumentNullException.ThrowIfNull(workspace);
        if (workspace.HasInvalidConfiguration) return new(null, "overlay.workspace_invalid_preset");
        if (!workspace.UsesModuleSources || workspace.Sources is null || !Current())
            return new(null, "overlay.identity_unavailable");
        try
        {
            // Preserve explicit module choices and hidden modules. Never attach
            // a room, community, account choice or temporary account selection.
            var context = new OverlaySourceResolutionContext(_key, _generation, _now(),
                OverlaySourceBinding.Automatic, null, null, new Dictionary<string, OverlaySourceLease>());
            return InformationOverlayModuleFrame.TryCapture(workspace.Sources, context, _ => null,
                Current, _ => false, activeModules: OverlayModuleSourceResolver.VisibleModules(workspace.Settings),
                signedOut: true);
        }
        catch { return new(null, "overlay.source_unavailable"); }
    }
}
