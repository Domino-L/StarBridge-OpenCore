using System.Runtime.InteropServices;
using StarBridge.Core.Overlay;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>
/// 0.7.3 m102: the primary screen as the visor sees it, for the size a preset the user never saved starts with
/// (OverlayVisorAutoSize). Read once per Host process; never throws (off Windows or on any failure it reports nothing
/// known, which picks the medium size).
/// </summary>
internal static class OverlayScreenProbe
{
    private static readonly Lazy<OverlayVisorSize> Picked = new(() => OverlayVisorAutoSize.Pick(Read()));

    /// <summary>The visor size for this screen.</summary>
    internal static OverlayVisorSize AutoVisorSize() => Picked.Value;

    /// <summary>
    /// The real pixel rows of the primary display (its current mode, which DPI virtualization does not touch), the
    /// Windows scaling (real rows over the rows this process is shown, or the system DPI when it sees them all) and the
    /// physical height Windows reports for it (VERTSIZE, from the display's EDID; OverlayVisorAutoSize ignores a value it
    /// does not believe).
    /// </summary>
    internal static OverlayScreenFacts Read()
    {
        if (!OperatingSystem.IsWindows()) return new(0, 1, null);
        try
        {
            var mode = new DevMode { dmSize = (short)Marshal.SizeOf<DevMode>() };
            var pixels = EnumDisplaySettings(null, EnumCurrentSettings, ref mode) ? mode.dmPelsHeight : 0;
            var logical = GetSystemMetrics(SmCyScreen);
            var scale = pixels > 0 && logical > 0 && pixels > logical ? (double)pixels / logical : SystemScale();
            if (pixels <= 0 && logical > 0) pixels = (int)Math.Round(logical * scale);
            double? mm = null;
            var dc = CreateDC("DISPLAY", null, null, IntPtr.Zero);
            if (dc != IntPtr.Zero)
            {
                try
                {
                    var height = GetDeviceCaps(dc, VertSize);
                    // GDI may answer its own estimate (rows at the logical DPI) instead of the display's size: that
                    // says nothing about the screen, so the fallback decides (review CX-OVERLAY-M102-R1 P2-6)
                    var rows = GetDeviceCaps(dc, VertRes);
                    var dpi = GetDeviceCaps(dc, LogPixelsY);
                    var estimate = rows > 0 && dpi > 0 ? rows * 25.4 / dpi : double.NaN;
                    if (height > 0 && !(Math.Abs(height - estimate) <= 1.5)) mm = height;
                }
                finally
                {
                    DeleteDC(dc);
                }
            }
            return new(pixels, scale, mm);
        }
        catch (Exception)
        {
            return new(0, 1, null);
        }
    }

    private static double SystemScale()
    {
        try
        {
            var dpi = GetDpiForSystem();
            return dpi > 0 ? dpi / 96.0 : 1;
        }
        catch (EntryPointNotFoundException)
        {
            return 1;
        }
    }

    private const int EnumCurrentSettings = -1, SmCyScreen = 1, VertSize = 6, VertRes = 10, LogPixelsY = 90;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplaySettingsW")]
    private static extern bool EnumDisplaySettings(string? deviceName, int modeNum, ref DevMode devMode);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForSystem();

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CreateDCW")]
    private static extern IntPtr CreateDC(string driver, string? device, string? output, IntPtr initData);

    [DllImport("gdi32.dll")]
    private static extern int GetDeviceCaps(IntPtr dc, int index);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr dc);
}
