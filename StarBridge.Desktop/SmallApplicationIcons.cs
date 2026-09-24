using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Microsoft.Win32;

namespace StarBridge.Desktop;

/// <summary>Owns small window/tray handles only; large Window.Icon stays intact.</summary>
internal sealed class SmallApplicationIcons : IDisposable
{
    private static SmallApplicationIcons? _current;
    private readonly Dispatcher _dispatcher;
    private readonly Dictionary<Window, WindowIcon> _windows = new();
    private bool _disposed;
    internal event Action? Changed;

    static SmallApplicationIcons()
    {
        EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((sender, args) =>
            {
                if (sender is Window window && ReferenceEquals(args.OriginalSource, window))
                    _current?.Attach(window);
            }));
    }

    internal SmallApplicationIcons(Dispatcher dispatcher)
    {
        _dispatcher = dispatcher;
        _current = this;
        SystemEvents.UserPreferenceChanged += OnPreferenceChanged;
    }

    internal Icon CreateTrayIcon()
    {
        var taskbar = FindWindow("Shell_TrayWnd", null);
        var dpi = taskbar != IntPtr.Zero ? GetDpiForWindow(taskbar) : GetDpiForSystem();
        return CreateIcon(GetSystemMetricsForDpi(49, dpi == 0 ? 96u : dpi));
    }

    private void Attach(Window window)
    {
        if (_disposed || _windows.ContainsKey(window)) return;
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero || HwndSource.FromHwnd(handle) is not { } source) return;
        var binding = new WindowIcon(handle, source);
        _windows.Add(window, binding);
        window.Closed += OnWindowClosed;
        binding.Refresh();
    }

    private void OnWindowClosed(object? sender, EventArgs args)
    {
        if (sender is not Window window) return;
        window.Closed -= OnWindowClosed;
        if (_windows.Remove(window, out var binding)) binding.Dispose();
    }

    private void OnPreferenceChanged(object sender, UserPreferenceChangedEventArgs args)
    {
        if (_disposed || _dispatcher.HasShutdownStarted) return;
        _dispatcher.BeginInvoke(new Action(() =>
        {
            if (_disposed) return;
            foreach (var binding in _windows.Values) binding.Refresh();
            Changed?.Invoke();
        }));
    }

    private static bool UsesDarkForeground()
    {
        var background = System.Windows.SystemColors.WindowColor;
        var fallback = background.R * 299 + background.G * 587 + background.B * 114 >= 128000;
        if (SystemParameters.HighContrast) return fallback;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("SystemUsesLightTheme") is int value ? value != 0 : fallback;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return fallback;
        }
    }

    private static Icon CreateIcon(int size)
    {
        var surface = UsesDarkForeground() ? "light_surface" : "dark_surface";
        var uri = new Uri($"pack://application:,,,/Assets/Brand/StarBridge_SmallIcon_{surface}.ico");
        using var stream = System.Windows.Application.GetResourceStream(uri)!.Stream;
        return LoadFrame(stream, size);
    }

    // System.Drawing's multi-frame constructor may interpret the ICO width byte
    // 0 incorrectly when selecting 256px. Select the PNG payload explicitly and
    // let Win32 create the requested physical-size HICON.
    internal static Icon LoadFrame(Stream stream, int size)
    {
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        var bytes = memory.ToArray();
        if (bytes.Length < 6 || BitConverter.ToUInt16(bytes, 2) != 1)
            throw new InvalidDataException("Invalid small icon resource.");
        var count = BitConverter.ToUInt16(bytes, 4);
        var bestEntry = -1;
        var bestScore = int.MaxValue;
        for (var i = 0; i < count; i++)
        {
            var entry = 6 + i * 16;
            if (entry + 16 > bytes.Length) throw new InvalidDataException("Truncated icon directory.");
            var width = bytes[entry] == 0 ? 256 : bytes[entry];
            var score = Math.Abs(width - size) * 2 + (width < size ? 1 : 0);
            if (score < bestScore) { bestScore = score; bestEntry = entry; }
        }
        if (bestEntry < 0) throw new InvalidDataException("Empty icon resource.");
        var length = BitConverter.ToUInt32(bytes, bestEntry + 8);
        var offset = BitConverter.ToUInt32(bytes, bestEntry + 12);
        if ((ulong)offset + length > (ulong)bytes.Length) throw new InvalidDataException("Truncated icon frame.");
        var frame = bytes.AsSpan((int)offset, (int)length).ToArray();
        var handle = CreateIconFromResourceEx(frame, length, true, 0x00030000, size, size, 0);
        if (handle == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            using var borrowed = Icon.FromHandle(handle);
            return (Icon)borrowed.Clone();
        }
        finally { DestroyIcon(handle); }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        SystemEvents.UserPreferenceChanged -= OnPreferenceChanged;
        foreach (var (window, binding) in _windows)
        {
            window.Closed -= OnWindowClosed;
            binding.Dispose();
        }
        _windows.Clear();
        if (ReferenceEquals(_current, this)) _current = null;
    }

    private sealed class WindowIcon : IDisposable
    {
        private readonly IntPtr _window;
        private readonly HwndSource _source;
        private Icon? _icon;
        internal WindowIcon(IntPtr window, HwndSource source)
        {
            _window = window;
            _source = source;
            source.AddHook(HandleMessage);
        }
        internal void Refresh()
        {
            var dpi = GetDpiForWindow(_window);
            var next = CreateIcon((int)Math.Round(24 * (dpi == 0 ? 96 : dpi) / 96.0));
            var previous = _icon;
            _icon = next;
            SendMessage(_window, 0x0080, IntPtr.Zero, next.Handle); // WM_SETICON / ICON_SMALL
            previous?.Dispose();
        }
        private IntPtr HandleMessage(IntPtr hwnd, int message, IntPtr wparam, IntPtr lparam, ref bool handled)
        {
            if (message == 0x007F && (wparam == IntPtr.Zero || wparam == new IntPtr(2)) && _icon is not null)
            {
                handled = true; // WM_GETICON / ICON_SMALL or ICON_SMALL2
                return _icon.Handle;
            }
            if (message == 0x02E0) Refresh(); // WM_DPICHANGED
            return IntPtr.Zero;
        }
        public void Dispose()
        {
            if (!_source.IsDisposed) _source.RemoveHook(HandleMessage);
            if (IsWindow(_window)) SendMessage(_window, 0x0080, IntPtr.Zero, IntPtr.Zero);
            _icon?.Dispose();
            _icon = null;
        }
    }

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr CreateIconFromResourceEx(byte[] bytes, uint length, bool icon, uint version, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll")] private static extern uint GetDpiForSystem();
    [DllImport("user32.dll")] private static extern int GetSystemMetricsForDpi(int index, uint dpi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string className, string? title);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wparam, IntPtr lparam);
}
