using System;
using System.Runtime.InteropServices;
using StarBridge.HostRuntime.HealthReading;
using StarBridge.HostRuntime.Presence;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace StarBridge.OverlayRuntime.Windows.HealthReading;

// The game window the health reader may capture: the foreground game window; with "游戏在后台时也读取" on
// (default off), also the game's main window while other windows cover it or the player works on another
// screen. Never a minimized window: it draws nothing then.
internal static class HudGameWindow
{
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
    delegate bool EnumWindowsProc(IntPtr window, IntPtr param);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr param);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect value, int size);

    const uint GwOwner = 4;
    // Look for the game's main window again at most this often (a process list and a window walk each time);
    // in between, the last choice is used while it still qualifies. Only while background reading is on and the
    // game is not in front.
    internal const long SearchEveryMilliseconds = 2000;
    static readonly object s_gate = new();
    static IntPtr s_background;
    static uint s_backgroundPid;
    static long s_lastSearch = -SearchEveryMilliseconds;

    // The window to read now, or zero: the foreground game window; with background reading allowed, else the
    // game's main window if it is shown and not minimized.
    public static IntPtr ReadableGameWindow(bool allowBackground)
    {
        var front = ForegroundGameWindow();
        if (front != IntPtr.Zero || !allowBackground) return front;
        var window = BackgroundGameWindow();
        return IsShown(window) ? window : IntPtr.Zero;
    }

    public static bool CanRead(bool allowBackground) => ReadableGameWindow(allowBackground) != IntPtr.Zero;

    // The window in front belongs to one of these processes (StarBridge's own: the Host and the client). One call each
    // to GetForegroundWindow and GetWindowThreadProcessId; no process is opened.
    public static bool ForegroundBelongsTo(IReadOnlyCollection<uint> processIds)
    {
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero) return false;
        GetWindowThreadProcessId(window, out var pid);
        return pid != 0 && processIds.Contains(pid);
    }

    // This exact window may still be read: it is the foreground window, or background reading is allowed and it
    // is still the game's shown, not minimized main window.
    public static bool MayRead(IntPtr window, bool allowBackground) =>
        IsForeground(window) || (allowBackground && IsShown(window) && window == BackgroundGameWindow());

    static bool IsShown(IntPtr window) => window != IntPtr.Zero && IsWindow(window) && IsWindowVisible(window) && !IsIconic(window);

    // The game's main top-level window (the largest unowned visible one of a StarCitizen process), minimized or
    // not (the caller decides whether it may be read). The choice is used only while it still qualifies (exists,
    // visible, unowned, same process) and is made again every SearchEveryMilliseconds from a fresh process list,
    // so a hidden old window, a new main window or a reused handle or process ID is noticed within that time.
    static IntPtr BackgroundGameWindow()
    {
        lock (s_gate)
        {
            var now = Environment.TickCount64;
            var previous = Qualifies(s_background, s_backgroundPid) ? s_background : IntPtr.Zero;
            if (!SearchDue(s_lastSearch, now)) return previous;
            s_lastSearch = now;
            var games = ProcessSnapshotNames.FindProcessIds(name => name.StartsWith("StarCitizen", StringComparison.OrdinalIgnoreCase));
            IntPtr best = IntPtr.Zero; uint bestPid = 0; long bestArea = -1; bool previousFound = false;
            if (games.Count > 0)
                EnumWindows((window, _) =>
                {
                    if (!IsWindowVisible(window) || GetWindow(window, GwOwner) != IntPtr.Zero) return true;
                    if (GetWindowThreadProcessId(window, out var owner) == 0 || !games.Contains(owner)) return true;
                    if (window == previous) previousFound = true;
                    long area = GetClientRect(window, out var rect) ? (long)Math.Max(0, rect.Right - rect.Left) * Math.Max(0, rect.Bottom - rect.Top) : 0;
                    if (area > bestArea) { best = window; bestPid = owner; bestArea = area; }
                    return true;
                }, IntPtr.Zero);
            // A minimized main window has no client area: keep it rather than switch to a smaller window meanwhile.
            if (previousFound && IsIconic(previous)) { best = previous; bestPid = s_backgroundPid; }
            s_background = best; s_backgroundPid = bestPid;
            return best;
        }
    }

    static bool Qualifies(IntPtr window, uint pid) =>
        window != IntPtr.Zero && IsWindow(window) && IsWindowVisible(window) && GetWindow(window, GwOwner) == IntPtr.Zero &&
        GetWindowThreadProcessId(window, out var owner) != 0 && owner == pid;

    internal static bool SearchDue(long lastSearch, long now) => now - lastSearch >= SearchEveryMilliseconds;

    // The foreground window if it belongs to a Star Citizen process, else zero.
    public static IntPtr ForegroundGameWindow()
    {
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero || IsIconic(window)) return IntPtr.Zero;
        GetWindowThreadProcessId(window, out var pid);
        if (pid == 0) return IntPtr.Zero;
        var name = ProcessSnapshotNames.FindForeground(pid);
        return name != null && name.StartsWith("StarCitizen", StringComparison.OrdinalIgnoreCase) ? window : IntPtr.Zero;
    }

    public static bool IsGameForeground() => ForegroundGameWindow() != IntPtr.Zero;

    // This exact window is the foreground window and not minimized.
    public static bool IsForeground(IntPtr window) => window != IntPtr.Zero && GetForegroundWindow() == window && !IsIconic(window);

    // The bottom-left HUD panel inside the captured window image. The image starts at the window's
    // visible frame (DWMWA_EXTENDED_FRAME_BOUNDS); the panel is 900x490 at 2560x1440 and scales
    // with the client height.
    public static bool TryPanelInImage(IntPtr window, int imageWidth, int imageHeight, out int x, out int y, out int w, out int h) =>
        TryPanelInImage(window, imageWidth, imageHeight, out x, out y, out w, out h, out _, out _);

    // Also the window's client size (the game's picture size; 11-17: the key for where digits were read clearly).
    public static bool TryPanelInImage(IntPtr window, int imageWidth, int imageHeight, out int x, out int y, out int w, out int h,
        out int clientWidth, out int clientHeight)
    {
        x = y = w = h = clientWidth = clientHeight = 0;
        if (!GetClientRect(window, out var cr)) return false;
        var p = new Point();
        if (!ClientToScreen(window, ref p)) return false;
        if (DwmGetWindowAttribute(window, 9 /* DWMWA_EXTENDED_FRAME_BOUNDS */, out var fb, Marshal.SizeOf<Rect>()) != 0) return false;
        int cw = cr.Right - cr.Left, ch = cr.Bottom - cr.Top;
        if (cw <= 0 || ch <= 0) return false;
        clientWidth = cw; clientHeight = ch;
        double s = ch / 1440.0;
        w = Math.Min((int)Math.Round(HudPanelFrame.W * s), cw); h = (int)Math.Round(HudPanelFrame.H * s);
        x = p.X - fb.Left; y = p.Y - fb.Top + ch - h;
        return x >= 0 && y >= 0 && x + w <= imageWidth && y + h <= imageHeight && w >= 32 && h >= 32;
    }
}

internal sealed class HudWindowCaptureFactory : IHudFrameSourceFactory
{
    readonly Func<bool> _background;

    // background: whether "游戏在后台时也读取" is on (read each time; a failing read counts as off).
    public HudWindowCaptureFactory(Func<bool>? background = null) => _background = background ?? (() => false);

    internal static bool Allowed(Func<bool> background)
    {
        try { return background(); } catch (Exception) { return false; }
    }

    public IHudFrameSource? TryCreate()
    {
        var window = HudGameWindow.ReadableGameWindow(Allowed(_background));
        if (window == IntPtr.Zero) return null;
        try { return HudWindowCapture.Create(window, _background); }
        catch (Exception) { return null; }
    }
}

// Windows Graphics Capture of the game window itself (created from the window handle), so other
// programs' windows on top of it never appear in the image. Only the bottom-left HUD panel is
// copied out of video memory (CopySubresourceRegion into a small staging texture on the GPU).
// Nothing is saved. On Windows versions that allow it the yellow capture border is turned off;
// older Windows 10 builds keep showing it. Every native object is created here, used on the
// reader thread, and released in Dispose.
internal sealed class HudWindowCapture : IHudFrameSource
{
    [ComImport, Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IGraphicsCaptureItemInterop
    {
        IntPtr CreateForWindow([In] IntPtr window, [In] ref Guid iid);
        IntPtr CreateForMonitor([In] IntPtr monitor, [In] ref Guid iid);
    }

    [ComImport, Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDirect3DDxgiInterfaceAccess
    {
        IntPtr GetInterface([In] ref Guid iid);
    }

    [DllImport("d3d11.dll", ExactSpelling = true)]
    static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    static readonly Guid ItemIid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    static readonly Guid TextureIid = typeof(ID3D11Texture2D).GUID;
    static int s_borderlessRequested;

    readonly IntPtr _window;
    readonly Func<bool> _background;
    // When the game draws nothing new, the last copy stands in for at most this long; after that a read reports no
    // frame, and the reader hides the ring once no frame has come for its 2 seconds (a window behind others or
    // on another screen may stop drawing; 11-13 user: no new image for over 2 seconds hides the ring).
    internal const long ReuseForMilliseconds = 250;
    long _lastNewFrameAt;

    // See IHudFrameSource: the reader counts only new images for its 2 seconds, and starts afresh once this
    // window may no longer be read (it is not the foreground window and not the game's current background window).
    public bool LastFrameWasNew { get; private set; }
    public bool TargetLost { get; private set; }
    ID3D11Device? _device; ID3D11DeviceContext? _context;
    IDirect3DDevice? _winrtDevice;
    GraphicsCaptureItem? _item;
    Direct3D11CaptureFramePool? _pool;
    GraphicsCaptureSession? _session;
    ID3D11Texture2D? _staging;
    global::Windows.Graphics.SizeInt32 _poolSize;
    int _rw, _rh;
    byte[] _region = Array.Empty<byte>();
    bool _haveFrame;

    // For diagnostics: whether the yellow border could be turned off on this system.
    internal bool BorderRemoved { get; private set; }

    HudWindowCapture(IntPtr window, Func<bool> background) { _window = window; _background = background; }

    public static HudWindowCapture Create(IntPtr window, Func<bool>? background = null)
    {
        var c = new HudWindowCapture(window, background ?? (() => false));
        try { c.Open(); return c; }
        catch { c.Dispose(); throw; }
    }

    static void RequestBorderlessOnce()
    {
        if (Interlocked.Exchange(ref s_borderlessRequested, 1) != 0) return;
        try
        {
            // Windows 11 / newer Windows 10: lets the session turn the yellow border off. No prompt for desktop apps.
            GraphicsCaptureAccess.RequestAccessAsync(GraphicsCaptureAccessKind.Borderless).AsTask().Wait(TimeSpan.FromSeconds(2));
        }
        catch (Exception) { }
    }

    void Open()
    {
        if (!GraphicsCaptureSession.IsSupported()) throw new InvalidOperationException("graphics capture is not supported");
        RequestBorderlessOnce();
        D3D11.D3D11CreateDevice(null, DriverType.Hardware, DeviceCreationFlags.BgraSupport,
            new[] { FeatureLevel.Level_11_0 }, out _device, out _context).CheckError();
        using (var dxgiDevice = _device!.QueryInterface<IDXGIDevice>())
        {
            Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.NativePointer, out var inspectable));
            try { _winrtDevice = MarshalInterface<IDirect3DDevice>.FromAbi(inspectable); }
            finally { Marshal.Release(inspectable); }
        }
        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInterop>();
        var iid = ItemIid;
        var itemPtr = interop.CreateForWindow(_window, ref iid);
        try { _item = GraphicsCaptureItem.FromAbi(itemPtr); }
        finally { Marshal.Release(itemPtr); }
        _poolSize = _item.Size;
        _pool = Direct3D11CaptureFramePool.CreateFreeThreaded(_winrtDevice, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, _poolSize);
        _session = _pool.CreateCaptureSession(_item);
        try { _session.IsCursorCaptureEnabled = false; } catch (Exception) { }
        try { _session.IsBorderRequired = false; BorderRemoved = true; } catch (Exception) { BorderRemoved = false; }
        _session.StartCapture();
    }

    // Only while the game window is the foreground window, or (background reading on) still shown and not
    // minimized. The newest window image is used; when no new image arrived (the game drew nothing new) the
    // last copy, made for the same layout, is reused for a moment (ReuseForMilliseconds).
    public bool TryCapture(HudPanelFrame frame)
    {
        LastFrameWasNew = false;
        if (_pool == null) return false;
        if (!HudGameWindow.MayRead(_window, HudWindowCaptureFactory.Allowed(_background))) { _haveFrame = false; TargetLost = true; return false; }
        Direct3D11CaptureFrame? latest = null;
        var fresh = false;
        try
        {
            // Drain to the newest frame so the reading is never behind.
            for (var f = _pool.TryGetNextFrame(); f != null; f = _pool.TryGetNextFrame()) { latest?.Dispose(); latest = f; }
            if (latest != null)
            {
                var size = latest.ContentSize;
                if (size.Width != _poolSize.Width || size.Height != _poolSize.Height)
                {
                    // The window changed size: rebuild the pool for the new size and skip this image.
                    _poolSize = size;
                    _pool.Recreate(_winrtDevice, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, size);
                    _haveFrame = false;
                    return false;
                }
                if (!HudGameWindow.TryPanelInImage(_window, size.Width, size.Height, out var x, out var y, out var w, out var h, out var cw, out var ch)) { _haveFrame = false; return false; }
                _clientSize = (cw, ch);
                if (_staging == null || w != _rw || h != _rh)
                {
                    _staging?.Dispose(); _staging = null;
                    _rw = w; _rh = h; _region = new byte[w * h * 4];
                    _staging = _device!.CreateTexture2D(new Texture2DDescription
                    {
                        Width = (uint)w, Height = (uint)h, MipLevels = 1, ArraySize = 1, Format = Format.B8G8R8A8_UNorm,
                        SampleDescription = new SampleDescription(1, 0), Usage = ResourceUsage.Staging, CPUAccessFlags = CpuAccessFlags.Read
                    });
                }
                // The frame's surface wrapper is released right away (11-13 performance check), not left to the
                // finalizer, so each image's reference to the window texture goes with the frame.
                using (var surface = latest.Surface)
                {
                    var access = surface.As<IDirect3DDxgiInterfaceAccess>();
                    var tiid = TextureIid;
                    var texPtr = access.GetInterface(ref tiid);
                    using (var texture = new ID3D11Texture2D(texPtr))
                        _context!.CopySubresourceRegion(_staging, 0, 0, 0, 0, texture, 0, new Vortice.Mathematics.Box(x, y, 0, x + w, y + h, 1));
                }
                var map = _context!.Map(_staging, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
                try
                {
                    for (int r = 0; r < h; r++) Marshal.Copy(map.DataPointer + (nint)(r * map.RowPitch), _region, r * w * 4, w * 4);
                }
                finally { _context.Unmap(_staging, 0); }
                _haveFrame = true;
                fresh = true;
                _lastNewFrameAt = Environment.TickCount64;
            }
        }
        finally { latest?.Dispose(); }
        if (!_haveFrame || (!fresh && !MayReuse(_lastNewFrameAt, Environment.TickCount64))) return false;
        LastFrameWasNew = fresh;
        HudPanelScaler.FromBgra(_region, _rw, _rh, frame);
        return true;
    }

    internal static bool MayReuse(long lastNewFrameAt, long now) => now - lastNewFrameAt <= ReuseForMilliseconds;

    // The game window's client size for the image read last (review R1 P2: the full picture size, not the HUD region,
    // which two picture sizes can share).
    (int Width, int Height) _clientSize;
    public (int Width, int Height) CaptureSize => _haveFrame ? _clientSize : (0, 0);

    public void Dispose()
    {
        try { _session?.Dispose(); } catch (Exception) { }
        _session = null;
        try { _pool?.Dispose(); } catch (Exception) { }
        _pool = null;
        _item = null;
        try { _winrtDevice?.Dispose(); } catch (Exception) { }
        _winrtDevice = null;
        _staging?.Dispose(); _staging = null;
        _context?.ClearState(); _context?.Dispose(); _context = null;
        _device?.Dispose(); _device = null;
    }
}
