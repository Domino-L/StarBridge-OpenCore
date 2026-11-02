namespace StarBridge.HostRuntime.Overlay;

/// <summary>Menu routes use 2..99; Host routes use 100/101 independently of a menu
/// session. Null binding removes a route. Invalid/conflicting bindings throw.</summary>
public interface ISafeHotkeyRuntime
{
    /// <summary>Shortcuts Windows refused to register while the user's choice is on;
    /// they keep working through Raw Input. Null when there are none.</summary>
    string? HotkeyRegistrationFailures => null;
    ValueTask ConfigureTemporaryHotkeyAsync(int commandId, string? binding,
        CancellationToken cancellationToken = default);
    ValueTask ConfigureHostHotkeyAsync(int commandId, string? binding, long lease,
        CancellationToken cancellationToken = default);
    event Action<int, long>? HostHotkeyTriggered;
}

public static class TemporaryHotkeyDefaults
{
    public const string Accept = "Ctrl+Alt+Y";
    public const string Decline = "Ctrl+Alt+N";
}
