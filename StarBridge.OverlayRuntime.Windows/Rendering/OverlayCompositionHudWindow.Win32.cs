using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using StarBridge.Core.Presence;
using SharpGen.Runtime;
using Vortice;
using Vortice.DCommon;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectComposition;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using D2DFactoryType = Vortice.Direct2D1.FactoryType;
using D2DTextAntialiasMode = Vortice.Direct2D1.TextAntialiasMode;
using D3DFeatureLevel = Vortice.Direct3D.FeatureLevel;
using D3D11Api = Vortice.Direct3D11.D3D11;
using DCompApi = Vortice.DirectComposition.DComp;
using DWriteFontStretch = Vortice.DirectWrite.FontStretch;
using DWriteFontStyle = Vortice.DirectWrite.FontStyle;
using DWriteFontWeight = Vortice.DirectWrite.FontWeight;
using DWriteFactoryType = Vortice.DirectWrite.FactoryType;
using DWriteTextAlignment = Vortice.DirectWrite.TextAlignment;
using DxgiAlphaMode = Vortice.DXGI.AlphaMode;
using DxgiFormat = Vortice.DXGI.Format;
using WpfRect = System.Windows.Rect;
using WpfVisibility = System.Windows.Visibility;

namespace StarBridge.Desktop;

/// <summary>Window messages, click-through, hit-trace diagnostics and small drawing helpers.</summary>
internal sealed partial class OverlayCompositionHudWindow
{
    private void EnableMouseClickThrough()
    {
        try
        {
            var handle = _source?.Handle ?? IntPtr.Zero;
            if (handle == IntPtr.Zero)
            {
                return;
            }

            OverlayHwndDiagnostics.ApplyClickThrough(handle, "experimental-hud-apply");
        }
        catch (Exception exception)
        {
            DesktopRuntimeDiagnostics.WriteCrashLog(exception);
        }
    }

    private static void LogPerformance(string operation, Stopwatch stopwatch, bool force = false)
    {
        stopwatch.Stop();
        if (!force &&
            stopwatch.ElapsedMilliseconds < SlowOperationThresholdMs &&
            !OverlayHwndDiagnostics.IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        DesktopRuntimeDiagnostics.WriteDiagnosticLog($"overlay-perf operation={operation} elapsedMs={stopwatch.Elapsed.TotalMilliseconds:F1}");
    }

    private void StartHitTraceDiagnostics()
    {
        if (!OverlayHwndDiagnostics.IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        var handle = _source?.Handle ?? IntPtr.Zero;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        _hitTraceDiagnosticsCount = 0;
        _hitTraceTimer?.Stop();
        _hitTraceTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(1)
        };
        _hitTraceTimer.Tick += (_, _) => LogRuntimeHitTrace(handle, "experimental-hud");
        _hitTraceTimer.Start();
        LogRuntimeHitTrace(handle, "experimental-hud");
    }

    private void LogRuntimeHitTrace(IntPtr handle, string label)
    {
        var count = ++_hitTraceDiagnosticsCount;
        OverlayHwndDiagnostics.LogMouseHitTest(handle, $"{label}-hit", count);
        if (count == 1 || count % 5 == 0)
        {
            OverlayHwndDiagnostics.LogVisibleTopLevelWindows($"{label}-windows", count);
        }
    }

    private IntPtr WindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        _menuZOrder.Constrain(msg, lParam);
        if (msg == WmNcHitTest)
        {
            OverlayHwndDiagnostics.LogMessage(hwnd, "experimental-hud", "WM_NCHITTEST", ++_hitTestDiagnosticsCount);
            handled = true;
            return new IntPtr(HtTransparent);
        }

        if (msg == WmMouseActivate)
        {
            OverlayHwndDiagnostics.LogMessage(hwnd, "experimental-hud", "WM_MOUSEACTIVATE", ++_mouseActivateDiagnosticsCount);
            handled = true;
            return new IntPtr(MaNoActivate);
        }

        if (IsMouseInputMessage(msg))
        {
            OverlayHwndDiagnostics.LogInputMessage(hwnd, "experimental-hud", MouseMessageName(msg), ++_mouseInputDiagnosticsCount);
        }

        return IntPtr.Zero;
    }

    private static bool IsMouseInputMessage(int msg)
    {
        return msg is WmMouseMove or
            WmLButtonDown or
            WmLButtonUp or
            WmRButtonDown or
            WmRButtonUp or
            WmMButtonDown or
            WmMButtonUp or
            WmMouseWheel or
            WmXButtonDown or
            WmXButtonUp;
    }

    private static string MouseMessageName(int msg)
    {
        return msg switch
        {
            WmMouseMove => "WM_MOUSEMOVE",
            WmLButtonDown => "WM_LBUTTONDOWN",
            WmLButtonUp => "WM_LBUTTONUP",
            WmRButtonDown => "WM_RBUTTONDOWN",
            WmRButtonUp => "WM_RBUTTONUP",
            WmMButtonDown => "WM_MBUTTONDOWN",
            WmMButtonUp => "WM_MBUTTONUP",
            WmMouseWheel => "WM_MOUSEWHEEL",
            WmXButtonDown => "WM_XBUTTONDOWN",
            WmXButtonUp => "WM_XBUTTONUP",
            _ => $"WM_0x{msg:X4}"
        };
    }

    private static RawRectF RectF(float x, float y, float width, float height)
    {
        return new Vortice.Mathematics.Rect(x, y, width, height);
    }

    private static RawRectF ResolveHorizontalRevealClip(
        float x,
        float y,
        float width,
        float height,
        double reveal,
        bool attachedOnRight)
    {
        var revealedWidth = Math.Max(0.5f, width * (float)Math.Clamp(reveal, 0, 1));
        return attachedOnRight
            ? RectF(x + width - revealedWidth, y - 4, revealedWidth + 4, height + 8)
            : RectF(x - 4, y - 4, revealedWidth + 4, height + 8);
    }

    private static float Segment01(float value, float start, float end)
    {
        if (end <= start)
        {
            return value >= end ? 1 : 0;
        }

        return Smooth01((value - start) / (end - start));
    }

    private static float Smooth01(float value)
    {
        var t = Math.Clamp(value, 0, 1);
        return t * t * (3 - 2 * t);
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hWnd);
}
