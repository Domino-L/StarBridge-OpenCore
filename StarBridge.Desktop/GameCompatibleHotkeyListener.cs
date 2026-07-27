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
    private const uint WmInput = 0x00FF;
    private const uint WmQuit = 0x0012;
    private const uint WmKeyDown = 0x0100;
    private const uint WmKeyUp = 0x0101;
    private const uint WmSysKeyDown = 0x0104;
    private const uint WmSysKeyUp = 0x0105;
    private const uint PmNoRemove = 0x0000;
    private const uint RidInput = 0x10000003;
    private const uint RimTypeKeyboard = 1;
    private const uint RidevRemove = 0x00000001;
    private const uint RidevInputSink = 0x00000100;
    private const ushort HidUsagePageGeneric = 0x01;
    private const ushort HidUsageGenericKeyboard = 0x06;
    private const int VkShift = 0x10;
    private const int VkControl = 0x11;
    private const int VkMenu = 0x12;
    private const int VkLeftWindows = 0x5B;
    private const int VkRightWindows = 0x5C;
    private static readonly IntPtr HwndMessage = new(-3);

    private readonly object _sync = new();
    private readonly NativeWindowProcedure _windowProcedure;
    private ManualResetEventSlim? _startupSignal;
    private Thread? _listenerThread;
    private GameCompatibleHotkeyTriggerFilter? _triggerFilter;
    private IntPtr _targetWindow;
    private uint _targetMessage;
    private IntPtr _rawInputWindow;
    private uint _listenerThreadId;
    private string? _windowClassName;
    private int _lastError;
    private bool _rawInputRegistered;
    private bool _disposed;

    internal GameCompatibleHotkeyListener()
    {
        _windowProcedure = HandleWindowMessage;
    }

    internal bool IsRunning
    {
        get
        {
            lock (_sync)
            {
                return _rawInputRegistered && _rawInputWindow != IntPtr.Zero;
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
            _windowClassName = $"StarBridge.RawInputHotkey.{Guid.NewGuid():N}";
            _listenerThread = new Thread(RunMessageLoop)
            {
                IsBackground = true,
                Name = "StarBridge.RawInputHotkey"
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
            _rawInputWindow = IntPtr.Zero;
            _rawInputRegistered = false;
            _windowClassName = null;
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
        string? windowClassName;
        lock (_sync)
        {
            _listenerThreadId = listenerThreadId;
            windowClassName = _windowClassName;
        }

        if (string.IsNullOrWhiteSpace(windowClassName))
        {
            CompleteStartup(error: 87);
            return;
        }

        var windowClass = new NativeWindowClass
        {
            Size = (uint)Marshal.SizeOf<NativeWindowClass>(),
            WindowProcedure = Marshal.GetFunctionPointerForDelegate(_windowProcedure),
            Instance = moduleHandle,
            ClassName = windowClassName
        };
        var classAtom = RegisterClassEx(ref windowClass);
        if (classAtom == 0)
        {
            CompleteStartup(Marshal.GetLastWin32Error());
            return;
        }

        var rawInputWindow = CreateWindowEx(
            0,
            windowClassName,
            string.Empty,
            0,
            0,
            0,
            0,
            0,
            HwndMessage,
            IntPtr.Zero,
            moduleHandle,
            IntPtr.Zero);
        if (rawInputWindow == IntPtr.Zero)
        {
            var error = Marshal.GetLastWin32Error();
            _ = UnregisterClass(windowClassName, moduleHandle);
            CompleteStartup(error);
            return;
        }

        var rawInputDevice = new RawInputDevice
        {
            UsagePage = HidUsagePageGeneric,
            Usage = HidUsageGenericKeyboard,
            Flags = RidevInputSink,
            Target = rawInputWindow
        };
        var registered = RegisterRawInputDevices(
            [rawInputDevice],
            1,
            (uint)Marshal.SizeOf<RawInputDevice>());
        var registrationError = registered ? 0 : Marshal.GetLastWin32Error();
        lock (_sync)
        {
            _rawInputWindow = rawInputWindow;
            _rawInputRegistered = registered;
            _lastError = registrationError;
            _startupSignal?.Set();
        }

        if (!registered)
        {
            _ = DestroyWindow(rawInputWindow);
            _ = UnregisterClass(windowClassName, moduleHandle);
            lock (_sync)
            {
                _rawInputWindow = IntPtr.Zero;
            }

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
            var removeDevice = new RawInputDevice
            {
                UsagePage = HidUsagePageGeneric,
                Usage = HidUsageGenericKeyboard,
                Flags = RidevRemove,
                Target = IntPtr.Zero
            };
            _ = RegisterRawInputDevices(
                [removeDevice],
                1,
                (uint)Marshal.SizeOf<RawInputDevice>());
            _ = DestroyWindow(rawInputWindow);
            _ = UnregisterClass(windowClassName, moduleHandle);
            lock (_sync)
            {
                _rawInputWindow = IntPtr.Zero;
                _rawInputRegistered = false;
                _listenerThreadId = 0;
            }
        }
    }

    private void CompleteStartup(int error)
    {
        lock (_sync)
        {
            _lastError = error;
            _rawInputWindow = IntPtr.Zero;
            _rawInputRegistered = false;
            _startupSignal?.Set();
        }
    }

    private IntPtr HandleWindowMessage(
        IntPtr window,
        uint message,
        UIntPtr wParam,
        IntPtr lParam)
    {
        if (message == WmInput)
        {
            ProcessRawKeyboardInput(lParam);
        }

        return DefWindowProc(window, message, wParam, lParam);
    }

    private void ProcessRawKeyboardInput(IntPtr rawInputHandle)
    {
        var headerSize = (uint)Marshal.SizeOf<RawInputHeader>();
        var dataSize = 0u;
        if (GetRawInputData(rawInputHandle, RidInput, IntPtr.Zero, ref dataSize, headerSize) != 0 ||
            dataSize < Marshal.SizeOf<RawInput>())
        {
            return;
        }

        var buffer = Marshal.AllocHGlobal((int)dataSize);
        try
        {
            var bytesRead = GetRawInputData(rawInputHandle, RidInput, buffer, ref dataSize, headerSize);
            if (bytesRead == uint.MaxValue || bytesRead != dataSize)
            {
                return;
            }

            var rawInput = Marshal.PtrToStructure<RawInput>(buffer);
            if (rawInput.Header.Type != RimTypeKeyboard)
            {
                return;
            }

            var keyboardMessage = rawInput.Keyboard.Message;
            var isKeyDown = keyboardMessage is WmKeyDown or WmSysKeyDown;
            var isKeyUp = keyboardMessage is WmKeyUp or WmSysKeyUp;
            if (!isKeyDown && !isKeyUp)
            {
                return;
            }

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
                    rawInput.Keyboard.VirtualKey,
                    ResolvePressedModifiers(),
                    isKeyDown,
                    IsInjected: false)) == true &&
                targetWindow != IntPtr.Zero &&
                targetMessage != 0)
            {
                _ = PostMessage(targetWindow, targetMessage, UIntPtr.Zero, IntPtr.Zero);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
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

    private delegate IntPtr NativeWindowProcedure(
        IntPtr window,
        uint message,
        UIntPtr wParam,
        IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeWindowClass
    {
        internal uint Size;
        internal uint Style;
        internal IntPtr WindowProcedure;
        internal int ClassExtra;
        internal int WindowExtra;
        internal IntPtr Instance;
        internal IntPtr Icon;
        internal IntPtr Cursor;
        internal IntPtr Background;
        internal string? MenuName;
        internal string ClassName;
        internal IntPtr IconSmall;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RawInputDevice
    {
        internal ushort UsagePage;
        internal ushort Usage;
        internal uint Flags;
        internal IntPtr Target;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct RawInputHeader
    {
        internal readonly uint Type;
        internal readonly uint Size;
        internal readonly IntPtr Device;
        internal readonly IntPtr WParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct RawKeyboard
    {
        internal readonly ushort MakeCode;
        internal readonly ushort Flags;
        internal readonly ushort Reserved;
        internal readonly ushort VirtualKey;
        internal readonly uint Message;
        internal readonly uint ExtraInformation;
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct RawInput
    {
        internal readonly RawInputHeader Header;
        internal readonly RawKeyboard Keyboard;
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

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassEx(ref NativeWindowClass windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool UnregisterClass(string className, IntPtr instance);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        IntPtr parent,
        IntPtr menu,
        IntPtr instance,
        IntPtr parameter);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(
        IntPtr window,
        uint message,
        UIntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(
        [In] RawInputDevice[] devices,
        uint deviceCount,
        uint deviceSize);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetRawInputData(
        IntPtr rawInput,
        uint command,
        IntPtr data,
        ref uint dataSize,
        uint headerSize);

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
