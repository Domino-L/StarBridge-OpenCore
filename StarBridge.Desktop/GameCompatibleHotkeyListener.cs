using System.Runtime.InteropServices;

namespace StarBridge.Desktop;

internal static class GameCompatibleHotkeyModifiers
{
    internal const uint Alt = 0x0001;
    internal const uint Control = 0x0002;
    internal const uint Shift = 0x0004;
    internal const uint Windows = 0x0008;
    internal const uint SupportedMask = Alt | Control | Shift | Windows;
}

internal readonly record struct GameCompatibleHotkeyBinding(uint VirtualKey, uint Modifiers);

internal readonly record struct GameCompatibleHotkeyInput(
    uint VirtualKey,
    uint PressedModifiers,
    bool IsKeyDown,
    bool IsInjected);

internal sealed class GameCompatibleHotkeyTriggerFilter
{
    private readonly GameCompatibleHotkeyBinding _binding;
    private bool _primaryKeyDown;

    internal GameCompatibleHotkeyTriggerFilter(GameCompatibleHotkeyBinding binding)
    {
        _binding = binding;
    }

    internal bool TryAccept(GameCompatibleHotkeyInput input)
    {
        if (input.VirtualKey != _binding.VirtualKey)
        {
            return false;
        }

        if (!input.IsKeyDown)
        {
            _primaryKeyDown = false;
            return false;
        }

        if (input.IsInjected || _primaryKeyDown)
        {
            return false;
        }

        _primaryKeyDown = true;
        return (input.PressedModifiers & GameCompatibleHotkeyModifiers.SupportedMask) ==
               (_binding.Modifiers & GameCompatibleHotkeyModifiers.SupportedMask);
    }
}

internal sealed class OverlayHotkeyTriggerGate
{
    private readonly object _sync = new();
    private readonly long _suppressionMilliseconds;
    private long? _lastAcceptedAt;

    internal OverlayHotkeyTriggerGate(TimeSpan suppressionWindow)
    {
        _suppressionMilliseconds = Math.Max(0, (long)Math.Ceiling(suppressionWindow.TotalMilliseconds));
    }

    internal bool TryAccept(long timestampMilliseconds)
    {
        lock (_sync)
        {
            if (_lastAcceptedAt is { } lastAcceptedAt &&
                timestampMilliseconds >= lastAcceptedAt &&
                timestampMilliseconds - lastAcceptedAt <= _suppressionMilliseconds)
            {
                return false;
            }

            _lastAcceptedAt = timestampMilliseconds;
            return true;
        }
    }

    internal void Reset()
    {
        lock (_sync)
        {
            _lastAcceptedAt = null;
        }
    }
}

internal sealed class GameCompatibleHotkeyListener : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const uint WmQuit = 0x0012;
    private const uint PmNoRemove = 0x0000;
    private const uint LlkhfLowerIlInjected = 0x00000002;
    private const uint LlkhfInjected = 0x00000010;
    private const int VkShift = 0x10;
    private const int VkControl = 0x11;
    private const int VkMenu = 0x12;
    private const int VkLeftWindows = 0x5B;
    private const int VkRightWindows = 0x5C;

    private readonly object _sync = new();
    private readonly LowLevelKeyboardProcedure _keyboardProcedure;
    private ManualResetEventSlim? _startupSignal;
    private Thread? _listenerThread;
    private GameCompatibleHotkeyTriggerFilter? _triggerFilter;
    private IntPtr _targetWindow;
    private uint _targetMessage;
    private IntPtr _hookHandle;
    private uint _listenerThreadId;
    private int _lastError;
    private bool _disposed;

    internal GameCompatibleHotkeyListener()
    {
        _keyboardProcedure = HandleKeyboardInput;
    }

    internal bool IsRunning
    {
        get
        {
            lock (_sync)
            {
                return _hookHandle != IntPtr.Zero;
            }
        }
    }

    internal int LastError
    {
        get
        {
            lock (_sync)
            {
                return _lastError;
            }
        }
    }

    internal bool Start(
        IntPtr targetWindow,
        uint targetMessage,
        GameCompatibleHotkeyBinding binding)
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(GameCompatibleHotkeyListener));
        }

        Stop();
        if (targetWindow == IntPtr.Zero || targetMessage == 0 || binding.VirtualKey == 0)
        {
            lock (_sync)
            {
                _lastError = 87;
            }

            return false;
        }

        var startupSignal = new ManualResetEventSlim(false);
        lock (_sync)
        {
            _targetWindow = targetWindow;
            _targetMessage = targetMessage;
            _triggerFilter = new GameCompatibleHotkeyTriggerFilter(binding);
            _lastError = 0;
            _startupSignal = startupSignal;
            _listenerThread = new Thread(RunMessageLoop)
            {
                IsBackground = true,
                Name = "StarBridge.GameCompatibleHotkey"
            };
            _listenerThread.Start();
        }

        if (!startupSignal.Wait(TimeSpan.FromSeconds(2)))
        {
            lock (_sync)
            {
                _lastError = 1460;
            }

            Stop();
            return false;
        }

        return IsRunning;
    }

    internal void Stop()
    {
        Thread? listenerThread;
        uint listenerThreadId;
        lock (_sync)
        {
            listenerThread = _listenerThread;
            listenerThreadId = _listenerThreadId;
        }

        if (listenerThreadId != 0)
        {
            _ = PostThreadMessage(listenerThreadId, WmQuit, UIntPtr.Zero, IntPtr.Zero);
        }

        if (listenerThread is { IsAlive: true } &&
            !ReferenceEquals(Thread.CurrentThread, listenerThread))
        {
            _ = listenerThread.Join(TimeSpan.FromSeconds(2));
        }

        lock (_sync)
        {
            _listenerThread = null;
            _listenerThreadId = 0;
            _targetWindow = IntPtr.Zero;
            _targetMessage = 0;
            _triggerFilter = null;
            _startupSignal?.Dispose();
            _startupSignal = null;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        Stop();
        _disposed = true;
    }

    private void RunMessageLoop()
    {
        var listenerThreadId = GetCurrentThreadId();
        _ = PeekMessage(out _, IntPtr.Zero, 0, 0, PmNoRemove);
        var moduleHandle = GetModuleHandle(null);
        var hookHandle = SetWindowsHookEx(
            WhKeyboardLl,
            _keyboardProcedure,
            moduleHandle,
            0);
        var error = hookHandle == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;

        ManualResetEventSlim? startupSignal;
        lock (_sync)
        {
            _listenerThreadId = listenerThreadId;
            _hookHandle = hookHandle;
            _lastError = error;
            startupSignal = _startupSignal;
        }

        startupSignal?.Set();
        if (hookHandle == IntPtr.Zero)
        {
            return;
        }

        try
        {
            while (GetMessage(out var message, IntPtr.Zero, 0, 0) > 0)
            {
                _ = TranslateMessage(ref message);
                _ = DispatchMessage(ref message);
            }
        }
        finally
        {
            _ = UnhookWindowsHookEx(hookHandle);
            lock (_sync)
            {
                _hookHandle = IntPtr.Zero;
                _listenerThreadId = 0;
            }
        }
    }

    private IntPtr HandleKeyboardInput(int code, UIntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 &&
            (wParam.ToUInt64() == WmKeyDown ||
             wParam.ToUInt64() == WmKeyUp ||
             wParam.ToUInt64() == WmSysKeyDown ||
             wParam.ToUInt64() == WmSysKeyUp))
        {
            var data = Marshal.PtrToStructure<LowLevelKeyboardInput>(lParam);
            var isKeyDown = wParam.ToUInt64() is WmKeyDown or WmSysKeyDown;
            var isInjected = (data.Flags & (LlkhfInjected | LlkhfLowerIlInjected)) != 0;
            GameCompatibleHotkeyTriggerFilter? triggerFilter;
            IntPtr targetWindow;
            uint targetMessage;
            lock (_sync)
            {
                triggerFilter = _triggerFilter;
                targetWindow = _targetWindow;
                targetMessage = _targetMessage;
            }

            if (triggerFilter?.TryAccept(new GameCompatibleHotkeyInput(
                    data.VirtualKey,
                    ResolvePressedModifiers(),
                    isKeyDown,
                    isInjected)) == true &&
                targetWindow != IntPtr.Zero &&
                targetMessage != 0)
            {
                _ = PostMessage(targetWindow, targetMessage, UIntPtr.Zero, IntPtr.Zero);
            }
        }

        return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
    }

    private static uint ResolvePressedModifiers()
    {
        var modifiers = 0u;
        if (IsPressed(VkMenu))
        {
            modifiers |= GameCompatibleHotkeyModifiers.Alt;
        }

        if (IsPressed(VkControl))
        {
            modifiers |= GameCompatibleHotkeyModifiers.Control;
        }

        if (IsPressed(VkShift))
        {
            modifiers |= GameCompatibleHotkeyModifiers.Shift;
        }

        if (IsPressed(VkLeftWindows) || IsPressed(VkRightWindows))
        {
            modifiers |= GameCompatibleHotkeyModifiers.Windows;
        }

        return modifiers;
    }

    private static bool IsPressed(int virtualKey)
    {
        return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    private delegate IntPtr LowLevelKeyboardProcedure(int code, UIntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct LowLevelKeyboardInput
    {
        internal readonly uint VirtualKey;
        internal readonly uint ScanCode;
        internal readonly uint Flags;
        internal readonly uint Time;
        internal readonly UIntPtr ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMessage
    {
        internal IntPtr Window;
        internal uint Message;
        internal UIntPtr WParam;
        internal IntPtr LParam;
        internal uint Time;
        internal NativePoint Point;
        internal uint Private;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        internal int X;
        internal int Y;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int hookType,
        LowLevelKeyboardProcedure procedure,
        IntPtr moduleHandle,
        uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hookHandle);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hookHandle,
        int code,
        UIntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(
        IntPtr window,
        uint message,
        UIntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostThreadMessage(
        uint threadId,
        uint message,
        UIntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("user32.dll")]
    private static extern int GetMessage(
        out NativeMessage message,
        IntPtr window,
        uint messageFilterMinimum,
        uint messageFilterMaximum);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref NativeMessage message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref NativeMessage message);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out NativeMessage message,
        IntPtr window,
        uint messageFilterMinimum,
        uint messageFilterMaximum,
        uint removeMessage);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? moduleName);
}
