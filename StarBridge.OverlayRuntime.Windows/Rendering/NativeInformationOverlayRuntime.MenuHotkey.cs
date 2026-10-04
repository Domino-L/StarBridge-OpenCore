namespace StarBridge.Desktop;

using System.Runtime.InteropServices;
using System.Windows.Threading;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime : IMenuHotkeyRuntime
{
    private const int MenuHotkeyCommand = 1;
    private readonly OverlayHotkeyTriggerGate _menuHotkeyGate = new(TimeSpan.FromMilliseconds(180));
    private MenuHotkeyRegistration? _menuHotkey;
    private string _menuHotkeyState = "disabled";
    private long _menuRequest;
    private string _menuPhase = "closed";
    private IntPtr _menuWindow;
    private bool MenuActive => _menuPhase is "opening" or "visible";

    public async ValueTask<string> ConfigureMenuHotkeyAsync(MenuHotkeyRegistration? registration,
        CancellationToken cancellationToken = default)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return "unavailable";
        return await dispatcher.InvokeAsync(() =>
        {
            if (_disposed || _controlThreadCleanedUp) return "unavailable";
            if (registration is null || !registration.SharesSessionWith(_menuHotkey))
            {
                // Replacement/revocation is not a normal menu close. Never
                // restore content belonging to the outgoing session.
                if (MenuActive) _ = CloseCore();
                _menuHotkey = registration;
                _menuRequest = 0;
                _menuPhase = "closed";
                _menuWindow = IntPtr.Zero;
                _menuHotkeyGate.Reset();
            }
            _menuHotkey = registration;
            ConfigureHotkey(_workspace?.HotkeyBinding ?? "", InformationHotkeyEnabled);
            return _menuHotkeyState;
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }

    private bool InformationHotkeyEnabled =>
        _workspace is { HotkeyEnabled: true, HasInvalidSourceConfiguration: false };

    public async ValueTask UpdateMenuWindowAsync(MenuHotkeyRegistration registration,
        long request, string phase, long window, CancellationToken cancellationToken = default)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return;
        await dispatcher.InvokeAsync(() =>
        {
            if (_disposed || !ReferenceEquals(_menuHotkey, registration) || !registration.IsCurrent() ||
                request <= 0 || request < _menuRequest || phase is not ("opening" or "visible" or "closed")) return;
            if (request > _menuRequest)
            {
                if (phase != "opening") return;
                _menuRequest = request;
                _menuPhase = phase;
                _menuWindow = IntPtr.Zero;
                _appearanceFocusTimer?.Stop();
                _appearanceFocusTimer = null;
                _window?.SetMenuAbove(IntPtr.Zero);
                _window?.StopStartupCover();
                return;
            }
            // Closed is terminal for this request; late visibility cannot
            // regain shortcut authority after logout/timeout/hide.
            if (_menuPhase == "closed") return;
            if (phase == "visible")
            {
                var handle = new IntPtr(window);
                _ = MenuGetWindowThreadProcessId(handle, out var pid);
                if (window <= 0 || pid != registration.ClientProcessId || !MenuIsWindow(handle)) return;
                _menuWindow = handle;
                _window?.SetMenuAbove(handle);
            }
            if (phase == "closed") _menuWindow = IntPtr.Zero;
            _menuPhase = phase;
            if (phase == "closed") _window?.SetMenuAbove(IntPtr.Zero);
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }

    private bool ValidateMenuInformationLayer()
    {
        if (!MenuActive) return false;
        if (_menuHotkey?.IsCurrent() != true)
        {
            _ = CloseCore();
            _menuPhase = "closed";
            _menuWindow = IntPtr.Zero;
            return false;
        }
        // Menu focus is not the game going into background. Keep current HUD
        // visibility and authority refresh; only the HWND stacking changes.
        RefreshWindow();
        return true;
    }

    private void HandleMenuHotkeyTrigger()
    {
        var registration = _menuHotkey;
        if (registration is null || !registration.Enabled || !registration.IsCurrent() ||
            _hotkeyPlan?.MenuState != OverlayHotkeyBindingState.Ready) return;
        var foreground = MenuGetForegroundWindow();
        if (_menuPhase == "opening") return;
        MenuHotkeyIntent intent;
        if (_menuPhase == "visible")
        {
            _ = MenuGetWindowThreadProcessId(foreground, out var pid);
            if (!registration.CloseWithHotkey || _menuWindow == IntPtr.Zero ||
                pid != registration.ClientProcessId ||
                MenuGetAncestor(foreground, 2) != _menuWindow) return;
            intent = new("close", _menuRequest, 0, 0);
        }
        else
        {
            // Runner revalidates this exact handle/PID immediately at Begin.
            if (!StarCitizenProcessProbe.TryCaptureForeground(out foreground, out var pid)) return;
            intent = new("open", 0, foreground.ToInt64(), checked((int)pid));
        }
        if (_menuHotkeyGate.TryAccept(unchecked((uint)GetMessageTime()))) registration.Trigger(intent);
    }

    [DllImport("user32.dll", EntryPoint = "GetForegroundWindow")]
    private static extern IntPtr MenuGetForegroundWindow();
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")]
    private static extern uint MenuGetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", EntryPoint = "GetAncestor")]
    private static extern IntPtr MenuGetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll", EntryPoint = "IsWindow")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MenuIsWindow(IntPtr window);
}
