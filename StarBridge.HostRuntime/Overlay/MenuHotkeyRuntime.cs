namespace StarBridge.HostRuntime.Overlay;

/// <summary>Only a process-local, authenticated primary subscription can own
/// this registration. It contains no persisted account data or keyboard hook.</summary>
public sealed record MenuHotkeyRegistration(
    string Binding,
    bool Enabled,
    bool CloseWithHotkey,
    int ClientProcessId,
    Func<bool> IsCurrent,
    Action<MenuHotkeyIntent> Trigger)
{
    private readonly object _sessionIdentity = new();
    // A settings edit (record clone) keeps window ownership. A new primary or
    // account registration never shares this token, even with the same keys.
    public bool SharesSessionWith(MenuHotkeyRegistration? other) =>
        other is not null && ReferenceEquals(_sessionIdentity, other._sessionIdentity);
}

public sealed record MenuHotkeyIntent(string Action, long Request, long TargetWindow, int TargetProcessId);

/// <summary>Shares the existing information-overlay raw-input owner. The
/// primary renderer still owns opening and its request/first-frame protocol.</summary>
public interface IMenuHotkeyRuntime
{
    ValueTask<string> ConfigureMenuHotkeyAsync(MenuHotkeyRegistration? registration,
        CancellationToken cancellationToken = default);
    ValueTask UpdateMenuWindowAsync(MenuHotkeyRegistration registration,
        long request, string phase, long window,
        CancellationToken cancellationToken = default);
}
