using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace StarBridge.Desktop;

internal static class OverlayHwndDiagnostics
{
    private const string DisableNoRedirectionEnv = "STARBRIDGE_OVERLAY_DISABLE_NOREDIRECTION";
    private const string ForceLayeredAlphaEnv = "STARBRIDGE_OVERLAY_FORCE_LAYERED_ALPHA";
    private const string EnableDiagnosticsEnv = "STARBRIDGE_OVERLAY_DIAGNOSTICS";
    private const string DisableNoRedirectionFile = "overlay.experimental.disable-noredirection";
    private const string ForceLayeredAlphaFile = "overlay.experimental.force-layered-alpha";
    private const string EnableDiagnosticsFile = "overlay.experimental.diagnostics";
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExLayered = 0x00080000;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExTopmost = 0x00000008;
    private const int WsExNoActivate = 0x08000000;
    private const int WsExNoRedirectionBitmap = 0x00200000;
    private const int GaRoot = 2;
    private const int SwpNoSize = 0x0001;
    private const int SwpNoMove = 0x0002;
    private const int SwpNoActivate = 0x0010;
    private const int SwpFrameChanged = 0x0020;
    private const int SwpShowWindow = 0x0040;
    private const uint LwaAlpha = 0x00000002;
    private static readonly IntPtr HwndTopmost = new(-1);

    public static int ClickThroughExtendedStyle => BuildClickThroughExtendedStyle(ReadOptions());

    public static bool IsVerboseDiagnosticsEnabled => ReadOptions().EnableVerboseDiagnostics;

    public static void EnsureTopmost(IntPtr handle, string label, bool force = false)
    {
        if (handle == IntPtr.Zero)
        {
            return;
        }

        var before = GetWindowLongPtr(handle, GwlExStyle);
        var alreadyTopmost = (before.ToInt64() & WsExTopmost) != 0;
        if (alreadyTopmost && !force)
        {
            return;
        }

        if (!alreadyTopmost)
        {
            var target = new IntPtr(before.ToInt64() | WsExTopmost);
            SetWindowLongPtr(handle, GwlExStyle, target);
        }

        var succeeded = SetWindowPos(
            handle,
            HwndTopmost,
            0,
            0,
            0,
            0,
            SwpNoMove | SwpNoSize | SwpNoActivate);
        if (!succeeded && IsVerboseDiagnosticsEnabled)
        {
            Write(label, $"ensure-topmost hwnd={FormatHandle(handle)} error={Marshal.GetLastWin32Error()}");
        }
    }

    public static void ApplyClickThrough(IntPtr handle, string label)
    {
        if (handle == IntPtr.Zero)
        {
            Write(label, "skip=null-hwnd");
            return;
        }

        var options = ReadOptions();
        var before = GetWindowLongPtr(handle, GwlExStyle);
        var target = new IntPtr(before.ToInt64() | unchecked((long)(uint)BuildClickThroughExtendedStyle(options)));
        var previous = SetWindowLongPtr(handle, GwlExStyle, target);
        var setStyleError = previous == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
        var after = GetWindowLongPtr(handle, GwlExStyle);
        var layeredAlphaOk = true;
        var layeredAlphaError = 0;
        if (options.ForceLayeredAlpha)
        {
            layeredAlphaOk = SetLayeredWindowAttributes(handle, 0, 255, LwaAlpha);
            layeredAlphaError = layeredAlphaOk ? 0 : Marshal.GetLastWin32Error();
        }

        var setWindowPosOk = SetWindowPos(
            handle,
            HwndTopmost,
            0,
            0,
            0,
            0,
            SwpNoMove | SwpNoSize | SwpNoActivate | SwpFrameChanged | SwpShowWindow);
        var setWindowPosError = setWindowPosOk ? 0 : Marshal.GetLastWin32Error();
        var hasRequiredStyle = HasClickThroughStyle(after, options);

        if (options.EnableVerboseDiagnostics || !hasRequiredStyle || setStyleError != 0 || !layeredAlphaOk || !setWindowPosOk)
        {
            Write(
                label,
                $"apply hwnd={FormatHandle(handle)} before={FormatStyle(before)} target={FormatStyle(target)} previous={FormatStyle(previous)} after={FormatStyle(after)} " +
                $"options={FormatOptions(options)} hasRequired={hasRequiredStyle} setStyleError={setStyleError} " +
                $"layeredAlpha={layeredAlphaOk} layeredAlphaError={layeredAlphaError} setWindowPos={setWindowPosOk} setWindowPosError={setWindowPosError} " +
                $"children={DescribeChildWindows(handle)}");
        }
    }

    public static void LogState(IntPtr handle, string label)
    {
        if (!IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        if (handle == IntPtr.Zero)
        {
            Write(label, "state=null-hwnd");
            return;
        }

        var style = GetWindowLongPtr(handle, GwlExStyle);
        var options = ReadOptions();
        Write(
            label,
            $"state hwnd={FormatHandle(handle)} exStyle={FormatStyle(style)} options={FormatOptions(options)} hasRequired={HasClickThroughStyle(style, options)} children={DescribeChildWindows(handle)}");
    }

    public static void LogMessage(IntPtr handle, string label, string messageName, int count)
    {
        if (!IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        if (count > 8)
        {
            return;
        }

        var style = handle == IntPtr.Zero ? IntPtr.Zero : GetWindowLongPtr(handle, GwlExStyle);
        Write(label, $"message={messageName} count={count} hwnd={FormatHandle(handle)} exStyle={FormatStyle(style)}");
    }

    public static void LogInputMessage(IntPtr handle, string label, string messageName, int count)
    {
        if (!IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        if (count > 16)
        {
            return;
        }

        var style = handle == IntPtr.Zero ? IntPtr.Zero : GetWindowLongPtr(handle, GwlExStyle);
        Write(label, $"input-message={messageName} count={count} hwnd={FormatHandle(handle)} exStyle={FormatStyle(style)}");
        LogMouseHitTest(handle, $"{label}-input-hit", count);
    }

    public static void LogMouseHitTest(IntPtr overlayHandle, string label, int count)
    {
        if (!IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        if (!GetCursorPos(out var cursor))
        {
            Write(label, $"mouse-hit count={count} cursor=unavailable error={Marshal.GetLastWin32Error()} overlay={FormatHandle(overlayHandle)}");
            return;
        }

        var hit = WindowFromPoint(cursor);
        var root = hit == IntPtr.Zero ? IntPtr.Zero : GetAncestor(hit, GaRoot);
        var foreground = GetForegroundWindow();
        Write(
            label,
            $"mouse-hit count={count} cursor=({cursor.X},{cursor.Y}) overlay={FormatHandle(overlayHandle)} hit=[{DescribeWindow(hit, overlayHandle)}] root=[{DescribeWindow(root, overlayHandle)}] foreground=[{DescribeWindow(foreground, overlayHandle)}]");
    }

    public static void LogVisibleTopLevelWindows(string label, int count)
    {
        if (!IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        var windows = new List<string>();
        EnumWindows(
            (window, lParam) =>
            {
                _ = lParam;
                if (!IsWindowVisible(window))
                {
                    return true;
                }

                GetWindowThreadProcessId(window, out var processId);
                if (processId == Environment.ProcessId || IsKnownStarBridgeProcess(processId))
                {
                    windows.Add(DescribeWindow(window, IntPtr.Zero));
                }

                return true;
            },
            IntPtr.Zero);

        Write(
            label,
            $"top-level count={count} starbridgeVisibleWindows={(windows.Count == 0 ? "none" : string.Join(" | ", windows))}");
    }

    public static void LogForegroundWindow(string label)
    {
        if (!IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        Write(label, $"foreground=[{DescribeWindow(GetForegroundWindow(), IntPtr.Zero)}]");
    }

    private static bool HasClickThroughStyle(IntPtr style, DiagnosticOptions options)
    {
        var value = style.ToInt64();
        var required = unchecked((long)(uint)BuildClickThroughExtendedStyle(options));
        return (value & required) == required;
    }

    private static int BuildClickThroughExtendedStyle(DiagnosticOptions options)
    {
        var style = WsExTopmost |
                    WsExTransparent |
                    WsExLayered |
                    WsExToolWindow |
                    WsExNoActivate;

        if (!options.DisableNoRedirectionBitmap)
        {
            style |= WsExNoRedirectionBitmap;
        }

        return style;
    }

    private static DiagnosticOptions ReadOptions()
    {
        return new DiagnosticOptions(
            IsOptionEnabled(DisableNoRedirectionEnv, DisableNoRedirectionFile),
            IsOptionEnabled(ForceLayeredAlphaEnv, ForceLayeredAlphaFile),
            IsOptionEnabled(EnableDiagnosticsEnv, EnableDiagnosticsFile));
    }

    private static bool IsOptionEnabled(string environmentName, string fileName)
    {
        var environmentValue = Environment.GetEnvironmentVariable(environmentName);
        if (!string.IsNullOrWhiteSpace(environmentValue))
        {
            return IsTruthy(environmentValue);
        }

        try
        {
            var path = Path.Combine(DesktopAppConfig.ConfigDirectory, fileName);
            if (!File.Exists(path))
            {
                return false;
            }

            var fileValue = File.ReadAllText(path).Trim();
            return fileValue.Length == 0 || IsTruthy(fileValue);
        }
        catch
        {
            return false;
        }
    }

    private static bool IsTruthy(string value)
    {
        return value.Equals("1", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("yes", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("on", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("enabled", StringComparison.OrdinalIgnoreCase);
    }

    private static string FormatOptions(DiagnosticOptions options)
    {
        return $"disableNoRedirection={options.DisableNoRedirectionBitmap},forceLayeredAlpha={options.ForceLayeredAlpha},verboseDiagnostics={options.EnableVerboseDiagnostics}";
    }

    private static string DescribeWindow(IntPtr handle, IntPtr overlayHandle)
    {
        if (handle == IntPtr.Zero)
        {
            return "hwnd=0x0";
        }

        var style = GetWindowLongPtr(handle, GwlExStyle);
        _ = GetWindowThreadProcessId(handle, out var processId);
        var processName = GetProcessName(processId);
        return $"hwnd={FormatHandle(handle)} rootEqualsOverlay={handle == overlayHandle} class={EscapeLogValue(GetWindowClassName(handle))} " +
               $"title={EscapeLogValue(GetWindowTitle(handle))} pid={processId} process={EscapeLogValue(processName)} " +
               $"starbridge={processId == Environment.ProcessId || IsKnownStarBridgeProcess(processId)} starCitizen={IsKnownStarCitizenProcess(processName)} " +
               $"visible={IsWindowVisible(handle)} rect={FormatRect(handle)} exStyle={FormatStyle(style)}";
    }

    private static string DescribeChildWindows(IntPtr handle)
    {
        var children = new List<string>();
        EnumChildWindows(
            handle,
            (child, _) =>
            {
                var className = GetWindowClassName(child);
                var style = GetWindowLongPtr(child, GwlExStyle);
                children.Add($"{FormatHandle(child)}:{className}:{FormatStyle(style)}");
                return true;
            },
            IntPtr.Zero);

        return children.Count == 0
            ? "none"
            : string.Join(",", children);
    }

    private static string GetWindowTitle(IntPtr handle)
    {
        var length = GetWindowTextLength(handle);
        if (length <= 0)
        {
            return "";
        }

        var builder = new StringBuilder(length + 1);
        return GetWindowText(handle, builder, builder.Capacity) > 0
            ? builder.ToString()
            : "";
    }

    private static string GetWindowClassName(IntPtr handle)
    {
        var builder = new StringBuilder(256);
        return GetClassName(handle, builder, builder.Capacity) > 0
            ? builder.ToString()
            : "unknown";
    }

    private static string GetProcessName(uint processId)
    {
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById((int)processId);
            return process.ProcessName;
        }
        catch
        {
            return "unknown";
        }
    }

    private static bool IsKnownStarBridgeProcess(uint processId)
    {
        if (processId == Environment.ProcessId)
        {
            return true;
        }

        var processName = GetProcessName(processId);
        return processName.Contains("Star Bridge", StringComparison.OrdinalIgnoreCase) ||
               processName.Contains("StarBridge", StringComparison.OrdinalIgnoreCase) ||
               processName.Contains("SC Fleet Command", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsKnownStarCitizenProcess(string processName)
    {
        return processName.Contains("StarCitizen", StringComparison.OrdinalIgnoreCase) ||
               processName.Contains("Star Citizen", StringComparison.OrdinalIgnoreCase);
    }

    private static string FormatRect(IntPtr handle)
    {
        return GetWindowRect(handle, out var rect)
            ? $"({rect.Left},{rect.Top},{rect.Right},{rect.Bottom})"
            : "(unknown)";
    }

    private static string FormatHandle(IntPtr handle)
    {
        return $"0x{handle.ToInt64():X}";
    }

    private static string FormatStyle(IntPtr style)
    {
        return $"0x{style.ToInt64():X}";
    }

    private static void Write(string label, string message)
    {
        App.WriteDiagnosticLog($"[OVERLAY-HWND] label={label} {message}");
    }

    private static string EscapeLogValue(string value)
    {
        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("|", "\\|", StringComparison.Ordinal)
            .Replace("\r", " ", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal);
    }

    private static IntPtr GetWindowLongPtr(IntPtr handle, int index)
    {
        return IntPtr.Size == 8
            ? GetWindowLongPtr64(handle, index)
            : new IntPtr(GetWindowLong32(handle, index));
    }

    private static IntPtr SetWindowLongPtr(IntPtr handle, int index, IntPtr value)
    {
        return IntPtr.Size == 8
            ? SetWindowLongPtr64(handle, index, value)
            : new IntPtr(SetWindowLong32(handle, index, value.ToInt32()));
    }

    private delegate bool EnumChildProc(IntPtr hwnd, IntPtr lParam);
    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    private readonly record struct DiagnosticOptions(bool DisableNoRedirectionBitmap, bool ForceLayeredAlpha, bool EnableVerboseDiagnostics);

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr64(IntPtr handle, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
    private static extern int GetWindowLong32(IntPtr handle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr64(IntPtr handle, int index, IntPtr value);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
    private static extern int SetWindowLong32(IntPtr handle, int index, int value);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint colorKey, byte alpha, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        int flags);

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(Point point);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr hWnd, int flags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
}
