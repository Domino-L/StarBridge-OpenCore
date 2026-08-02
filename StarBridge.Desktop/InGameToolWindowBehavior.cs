using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace StarBridge.Desktop;

internal static class InGameToolWindowBehavior
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExNoActivate = 0x08000000;
    private const int WM_SYSCOMMAND = 0x0112;
    private const int WM_NCLBUTTONDBLCLK = 0x00A3;
    private const int WmEnterSizeMove = 0x0231;
    private const int WmExitSizeMove = 0x0232;
    private const int SystemCommandMask = 0xFFF0;
    private const int SC_MAXIMIZE = 0xF030;
    private const int HitTestCaption = 2;
    private static readonly ConditionalWeakTable<Window, SnapMaximizeGuard>
        SnapMaximizeGuards = new();
    private static readonly ConditionalWeakTable<Window, MoveLoopObserver>
        MoveLoopObservers = new();

    internal static void PreventSnapMaximize(Window window)
    {
        ArgumentNullException.ThrowIfNull(window);
        _ = SnapMaximizeGuards.GetValue(
            window,
            static guardedWindow => new SnapMaximizeGuard(guardedWindow));
    }

    internal static void SetTransientOwner(Window window, Window? owner)
    {
        ArgumentNullException.ThrowIfNull(window);
        var ownerHandle = owner is null
            ? IntPtr.Zero
            : new WindowInteropHelper(owner).Handle;
        new WindowInteropHelper(window).Owner = ownerHandle;
    }

    internal static void TrackMoveLoop(
        Window window,
        Action<Window, bool> stateChanged)
    {
        ArgumentNullException.ThrowIfNull(window);
        ArgumentNullException.ThrowIfNull(stateChanged);
        if (MoveLoopObservers.TryGetValue(window, out var existing))
        {
            existing.SetStateChanged(stateChanged);
            return;
        }

        MoveLoopObservers.Add(window, new MoveLoopObserver(window, stateChanged));
    }

    internal static void SetClickThrough(Window window, bool enabled)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            if (enabled)
            {
                window.SourceInitialized += EnableAfterSourceInitialized;
            }

            return;
        }

        var style = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        var next = enabled
            ? style | WsExTransparent | WsExNoActivate
            : style & ~(WsExTransparent | WsExNoActivate);
        if (next != style)
        {
            _ = SetWindowLongPtr(handle, GwlExStyle, new IntPtr(next));
        }

        if (!enabled)
        {
            window.SourceInitialized -= EnableAfterSourceInitialized;
        }
    }

    internal static bool TakeForegroundInput(Window window)
    {
        ArgumentNullException.ThrowIfNull(window);
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            return false;
        }

        if (GetForegroundWindow() == handle)
        {
            _ = SetFocus(handle);
            return true;
        }

        _ = SetForegroundWindow(handle);
        if (GetForegroundWindow() == handle)
        {
            _ = SetActiveWindow(handle);
            _ = SetFocus(handle);
            return true;
        }

        var foregroundHandle = GetForegroundWindow();
        var foregroundThreadId = foregroundHandle == IntPtr.Zero
            ? 0
            : GetWindowThreadProcessId(foregroundHandle, out _);
        var currentThreadId = GetCurrentThreadId();
        var inputAttached = false;
        try
        {
            if (foregroundThreadId != 0 && foregroundThreadId != currentThreadId)
            {
                inputAttached = AttachThreadInput(
                    currentThreadId,
                    foregroundThreadId,
                    attach: true);
            }

            _ = BringWindowToTop(handle);
            _ = SetForegroundWindow(handle);
            _ = SetActiveWindow(handle);
            _ = SetFocus(handle);
        }
        finally
        {
            if (inputAttached)
            {
                _ = AttachThreadInput(
                    currentThreadId,
                    foregroundThreadId,
                    attach: false);
            }
        }

        return GetForegroundWindow() == handle;
    }

    private static void EnableAfterSourceInitialized(object? sender, EventArgs e)
    {
        if (sender is Window window)
        {
            window.SourceInitialized -= EnableAfterSourceInitialized;
            SetClickThrough(window, true);
        }
    }

    private static IntPtr GetWindowLongPtr(IntPtr windowHandle, int index) =>
        IntPtr.Size == 8
            ? GetWindowLongPtr64(windowHandle, index)
            : new IntPtr(GetWindowLong32(windowHandle, index));

    private static IntPtr SetWindowLongPtr(IntPtr windowHandle, int index, IntPtr value) =>
        IntPtr.Size == 8
            ? SetWindowLongPtr64(windowHandle, index, value)
            : new IntPtr(SetWindowLong32(windowHandle, index, value.ToInt32()));

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong32(IntPtr windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern int SetWindowLong32(IntPtr windowHandle, int index, int value);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr windowHandle, int index, IntPtr value);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr windowHandle);

    [DllImport("user32.dll")]
    private static extern bool BringWindowToTop(IntPtr windowHandle);

    [DllImport("user32.dll")]
    private static extern IntPtr SetActiveWindow(IntPtr windowHandle);

    [DllImport("user32.dll")]
    private static extern IntPtr SetFocus(IntPtr windowHandle);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(
        IntPtr windowHandle,
        out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool AttachThreadInput(
        uint attachThreadId,
        uint attachToThreadId,
        [MarshalAs(UnmanagedType.Bool)] bool attach);

    private sealed class SnapMaximizeGuard
    {
        private readonly Window _window;
        private HwndSource? _source;
        private bool _restoringState;

        internal SnapMaximizeGuard(Window window)
        {
            _window = window;
            _window.SourceInitialized += Window_SourceInitialized;
            _window.StateChanged += Window_StateChanged;
            _window.Closed += Window_Closed;

            if (new WindowInteropHelper(_window).Handle != IntPtr.Zero)
            {
                AttachNativeHook();
            }
        }

        private void Window_SourceInitialized(object? sender, EventArgs e) =>
            AttachNativeHook();

        private void AttachNativeHook()
        {
            if (_source is not null)
            {
                return;
            }

            _source = HwndSource.FromHwnd(new WindowInteropHelper(_window).Handle);
            _source?.AddHook(WindowProcedure);
        }

        private IntPtr WindowProcedure(
            IntPtr windowHandle,
            int message,
            IntPtr wParam,
            IntPtr lParam,
            ref bool handled)
        {
            var nativeValue = wParam.ToInt64();
            var command = nativeValue & SystemCommandMask;
            if ((message == WM_SYSCOMMAND && command == SC_MAXIMIZE) ||
                (message == WM_NCLBUTTONDBLCLK &&
                 nativeValue == HitTestCaption))
            {
                handled = true;
            }

            return IntPtr.Zero;
        }

        private void Window_StateChanged(object? sender, EventArgs e)
        {
            if (_restoringState || _window.WindowState != WindowState.Maximized)
            {
                return;
            }

            _restoringState = true;
            _window.WindowState = WindowState.Normal;
            _restoringState = false;
        }

        private void Window_Closed(object? sender, EventArgs e)
        {
            _window.SourceInitialized -= Window_SourceInitialized;
            _window.StateChanged -= Window_StateChanged;
            _window.Closed -= Window_Closed;
            _source?.RemoveHook(WindowProcedure);
            _source = null;
        }
    }

    private sealed class MoveLoopObserver
    {
        private readonly Window _window;
        private HwndSource? _source;
        private Action<Window, bool> _stateChanged;
        private bool _isMoving;

        internal MoveLoopObserver(
            Window window,
            Action<Window, bool> stateChanged)
        {
            _window = window;
            _stateChanged = stateChanged;
            _window.SourceInitialized += Window_SourceInitialized;
            _window.Closed += Window_Closed;

            if (new WindowInteropHelper(_window).Handle != IntPtr.Zero)
            {
                AttachNativeHook();
            }
        }

        internal void SetStateChanged(Action<Window, bool> stateChanged) =>
            _stateChanged = stateChanged;

        private void Window_SourceInitialized(object? sender, EventArgs e) =>
            AttachNativeHook();

        private void AttachNativeHook()
        {
            if (_source is not null)
            {
                return;
            }

            _source = HwndSource.FromHwnd(new WindowInteropHelper(_window).Handle);
            _source?.AddHook(WindowProcedure);
        }

        private IntPtr WindowProcedure(
            IntPtr windowHandle,
            int message,
            IntPtr wParam,
            IntPtr lParam,
            ref bool handled)
        {
            if (message == WmEnterSizeMove)
            {
                SetMoving(true);
            }
            else if (message == WmExitSizeMove)
            {
                SetMoving(false);
            }

            return IntPtr.Zero;
        }

        private void SetMoving(bool moving)
        {
            if (_isMoving == moving)
            {
                return;
            }

            _isMoving = moving;
            _stateChanged(_window, moving);
        }

        private void Window_Closed(object? sender, EventArgs e)
        {
            SetMoving(false);
            _window.SourceInitialized -= Window_SourceInitialized;
            _window.Closed -= Window_Closed;
            _source?.RemoveHook(WindowProcedure);
            _source = null;
        }
    }
}
