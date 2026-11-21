using System.Diagnostics;
using System.Reflection;
using SharpGen.Runtime;
using StarBridge.Core.Overlay;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// 11-08 (build 80 NativeHost: about 165 NVIDIA driver threads and several hundred MB that never went away): the
/// HUD released its D3D11 device on close, but Vortice adds a COM reference on every read of an effect's Output,
/// and the visor renderer never released those, so each overlay opening kept one whole device (about 50 driver
/// threads) until the process exited. These checks count the references left once everything is closed.
/// </summary>
internal static class OverlayDeviceReleaseTests
{
    private static readonly BindingFlags All = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;

    private static void Check(bool value, string name, object? evidence = null)
    {
        if (!value) throw new InvalidOperationException($"FAIL {name} {evidence}");
        Console.WriteLine($"PASS {name} {evidence}");
    }

    private static object? Call(object target, string name, params object?[] values) =>
        target.GetType().GetMethods(All).Single(m => m.Name == name && m.GetParameters().Length == values.Length).Invoke(target, values);

    /// <summary>References on a COM object other than the caller's own (AddRef returns the new count; Release the one after).</summary>
    private static uint OtherReferences(ComObject value)
    {
        value.AddRef();
        return value.Release() - 1;
    }

    internal static void Run()
    {
        RendererReleasesDevice();
        HudReleasesDeviceOnClose();
        RepeatedOpeningsDoNotAccumulate();
    }

    private static int ThreadCount()
    {
        using var process = Process.GetCurrentProcess();
        process.Refresh();
        return process.Threads.Count;
    }

    /// <summary>The thread count once four samples in a row (400 ms apart) agree; driver threads leave a moment after
    /// the device goes. Gives the last sample after 12 seconds.</summary>
    private static int SettledThreadCount()
    {
        var settle = Stopwatch.StartNew();
        var previous = ThreadCount();
        var same = 1;
        while (settle.ElapsedMilliseconds < 12000)
        {
            Thread.Sleep(400);
            var now = ThreadCount();
            same = now == previous ? same + 1 : 1;
            previous = now;
            if (same >= 4) break;
        }
        return previous;
    }

    /// <summary>Open and close a real visor HUD three times after one warm-up opening: every close leaves no reference on
    /// its device (the hard check), and the threads a device brings (about 50 with an NVIDIA driver; a kept device adds
    /// them again on every opening) do not pile up: after the third close the process has at most 20 more threads than
    /// after the first, room for the runtime's own pool but well under one kept device.</summary>
    private static void RepeatedOpeningsDoNotAccumulate()
    {
        Check(OpenAndClose(out _) == 0, "device release: the warm-up opening leaves no reference on its device");
        var lefts = new List<uint>();
        var threads = new List<int>();
        for (var opening = 1; opening <= 3; opening++)
        {
            lefts.Add(OpenAndClose(out _));
            threads.Add(SettledThreadCount());
        }
        Check(lefts.All(left => left == 0), "device release: three openings in a row, each close leaves no reference on its device", new { Left = string.Join(",", lefts) });
        Check(threads[2] <= threads[0] + 20, "device release: three openings in a row do not pile up threads", new { Threads = string.Join(",", threads) });
    }

    /// <summary>Off screen: the visor renderer draws every group (with a scrolling chat line) on its own WARP device; once
    /// the renderer and the D2D objects are disposed, nothing but the test holds the device.</summary>
    private static void RendererReleasesDevice()
    {
        var d3d = D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        try
        {
            using (var dxgi = d3d.QueryInterface<IDXGIDevice>())
            using (var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>())
            using (var device = factory.CreateDevice(dxgi))
            using (var dc = device.CreateDeviceContext(DeviceContextOptions.None))
            using (var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>())
            {
                dc.SetDpi(96, 96);
                const int W = 1920, H = 1080;
                var pf = new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied);
                using var overlay = dc.CreateBitmap(new SizeI(W, H), IntPtr.Zero, 0, new BitmapProperties1(pf, 96, 96, BitmapOptions.Target));
                using var renderer = new OverlayVisorRenderer(dc, dw);
                using var window = OverlayVisorTests.Window(30, W, H);
                var scene = (OverlayVisorScene)Call(window, "BuildVisorScene", Call(window, "BuildFrameState"))!;
                var shown = scene with
                {
                    ShowEvents = true, ShowChat = true,
                    Events = [new("到达", "Vega 到达奥里森", "20:41", 1, 1)],
                    Chat = [new("Aster", "这一条聊天写得很长很长，长到放不下，所以面罩会让它在格子里来回滚动，测试滚动层也会释放", 1)],
                    ShowNotice = true, NoticeTitle = "舰队召集", NoticeBody = "今晚八点奥里森集合", NoticeTimer = "剩余 27:30", NoticeIsRally = true,
                    DirectMessage = "Vega 发来私信",
                };
                foreach (var now in new[] { 10.0, 10.5, 20, 30, 31.5 })
                    renderer.Render(overlay, System.Numerics.Vector2.Zero, shown, W, H, now);
                Check(renderer.ScrollFields > 0, "device release: the scene draws every group and a scrolling field", new { renderer.ScrollFields });
            }

            var others = OtherReferences(d3d);
            Check(others == 0, "device release: once the visor renderer and its D2D objects are disposed, nothing else holds the D3D11 device",
                new { Others = others });
        }
        finally
        {
            d3d.Dispose();
        }
    }

    /// <summary>A real visor HUD (a small click-through window, about a second): after Close, the device it created has no
    /// references left except the one this test took.</summary>
    private static void HudReleasesDeviceOnClose()
    {
        var left = OpenAndClose(out var committed);
        Check(left == 0, "device release: after the visor HUD closes, its D3D11 device has no references left (the driver threads can go)",
            new { Left = left, committed });
    }

    /// <summary>Shows a visor HUD, takes a reference of its own on the HUD's device, closes the HUD, waits until its render
    /// thread has finished (the device is released near the end of the clean-up, after the disposed flag is set), and
    /// returns how many references other than the test's own the device still has (0: the device goes with it).</summary>
    private static uint OpenAndClose(out bool committed)
    {
        var window = OverlayVisorTests.Window(5, 480, 320);
        ID3D11Device? device = null;
        try
        {
            try
            {
                window.Show();
                var wait = Stopwatch.StartNew();
                while (!window.FirstFrameCommitted && wait.ElapsedMilliseconds < 5000) Thread.Sleep(20);
                committed = window.FirstFrameCommitted;
                Check(committed, "device release: the visor HUD commits its first frame");
                // a wrapper of our own: the HUD's Dispose clears its wrapper, not the native object
                if (typeof(OverlayCompositionHudWindow).GetField("_d3dDevice", All)!.GetValue(window) is ID3D11Device hud)
                {
                    device = new ID3D11Device(hud.NativePointer);
                    device.AddRef();
                }
                Thread.Sleep(400); // a few more frames through the same device
            }
            finally
            {
                window.Close();
            }

            var thread = (Thread?)typeof(OverlayCompositionHudWindow).GetField("_thread", All)!.GetValue(window);
            var finished = thread is not null && thread.Join(10000);
            var disposed = (bool)typeof(OverlayCompositionHudWindow).GetField("_renderThreadDisposed", All)!.GetValue(window)!;
            Check(device is not null && finished && disposed, "device release: the HUD closes, disposes and its render thread ends",
                new { Device = device is not null, finished, disposed });
            return OtherReferences(device!);
        }
        finally
        {
            device?.Dispose(); // the test's own reference, whatever above throws
        }
    }
}
