using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;
using WpfFlowDirection = System.Windows.FlowDirection;

namespace StarBridge.Desktop;

public sealed class OverlayStartupTransitionLayer : FrameworkElement
{
    public const double DurationMs = 2150;
    private const double TakeoverEnd = 0.18;
    private const double ConsoleOpenStart = 0.18;
    private const double CompletionStart = 0.73;
    public const double ProgressCompleteFadeStartMs = DurationMs * (CompletionStart + 0.06);
    private const double SweepStart = 0.76;
    private const double FadeStart = 0.88;
    private static readonly Typeface MonoTypeface = new(new FontFamily("Consolas"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
    private static readonly Typeface MonoBoldTypeface = new(new FontFamily("Consolas"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
    private static readonly Typeface UiTypeface = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
    private static readonly Typeface UiBoldTypeface = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
    private static readonly int[] StatusChipIndexes = [0, 3, 4, 6];

    private readonly List<Rect> _revealTargets = [];
    private readonly Dictionary<uint, SolidColorBrush> _brushCache = [];
    private DateTime _startedAt;
    private DateTime _lastInvalidatedAt;
    private double _targetFrameIntervalMs = GetTargetFrameIntervalMs(OverlayStartupTransitionFrameRate.Fps30);
    private bool _isActive;
    private bool _isStaticSnapshot;
    private double _staticSnapshotProgress;
    private System.Windows.Threading.DispatcherTimer? _staticSnapshotTimer;
    private string _language = "zh";
    private double _pixelsPerDip = 1.0;
    private OverlayStartupTransitionContext _context = OverlayStartupTransitionContext.Default;
    private TerminalTransitionPalette _palette = TerminalTransitionPalette.Default;
    private IReadOnlyList<OverlayStartupStatusStep> StatusSteps => _context.StatusSteps.Count >= 7
        ? _context.StatusSteps
        : OverlayStartupTransitionContext.Default.StatusSteps;
    private IReadOnlyList<string> TerminalLines => _context.TerminalLines.Count > 0
        ? _context.TerminalLines
        : OverlayStartupTransitionContext.Default.TerminalLines;

    public OverlayStartupTransitionLayer()
    {
        Visibility = Visibility.Collapsed;
        IsHitTestVisible = false;
        SnapsToDevicePixels = true;
    }

    public bool Start(OverlayDisplaySettings settings, string language, OverlayStartupTransitionContext? context)
    {
        if (!settings.EnableStartupTransition ||
            settings.StartupTransitionStyle != OverlayStartupTransitionStyle.BridgeTerminal)
        {
            Stop();
            return false;
        }

        _language = language;
        _context = context ?? OverlayStartupTransitionContext.Default;
        ApplyPalette(settings);
        ApplyFrameRate(settings);
        _startedAt = DateTime.UtcNow;
        _lastInvalidatedAt = DateTime.MinValue;
        Visibility = Visibility.Visible;

        if (!_isActive)
        {
            CompositionTarget.Rendering += CompositionTarget_Rendering;
            _isActive = true;
        }

        InvalidateVisual();
        return true;
    }

    public void ApplySettings(OverlayDisplaySettings settings, OverlayStartupTransitionContext? context)
    {
        _context = context ?? OverlayStartupTransitionContext.Default;
        ApplyPalette(settings);
        ApplyFrameRate(settings);

        if (!settings.EnableStartupTransition)
        {
            Stop();
        }
    }

    public void Stop()
    {
        _staticSnapshotTimer?.Stop();
        _staticSnapshotTimer = null;
        _isStaticSnapshot = false;

        if (_isActive)
        {
            CompositionTarget.Rendering -= CompositionTarget_Rendering;
            _isActive = false;
        }

        Visibility = Visibility.Collapsed;
        InvalidateVisual();
    }

    public void SetRevealTargets(IEnumerable<Rect> targets)
    {
        _revealTargets.Clear();
        foreach (var target in targets)
        {
            if (target.Width > 1 && target.Height > 1)
            {
                _revealTargets.Add(target);
            }
        }

        if (_isActive)
        {
            InvalidateVisual();
        }
    }

    internal bool ShowStaticSnapshot(
        OverlayDisplaySettings settings,
        string language,
        OverlayStartupTransitionContext? context,
        IEnumerable<Rect> targets,
        double progress)
    {
        if (!settings.EnableStartupTransition ||
            settings.StartupTransitionStyle != OverlayStartupTransitionStyle.BridgeTerminal)
        {
            Stop();
            return false;
        }

        if (_isActive)
        {
            CompositionTarget.Rendering -= CompositionTarget_Rendering;
            _isActive = false;
        }

        _language = language;
        _context = context ?? OverlayStartupTransitionContext.Default;
        ApplyPalette(settings);
        ApplyFrameRate(settings);
        _staticSnapshotProgress = Clamp(progress, 0, 1);
        _isStaticSnapshot = true;
        Visibility = Visibility.Visible;
        SetRevealTargets(targets);

        _staticSnapshotTimer?.Stop();
        _staticSnapshotTimer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(DurationMs + 90)
        };
        _staticSnapshotTimer.Tick += (_, _) => Stop();
        _staticSnapshotTimer.Start();

        InvalidateVisual();
        return true;
    }

    internal static RenderTargetBitmap RenderSnapshot(
        double width,
        double height,
        double progress,
        OverlayDisplaySettings settings,
        string language,
        OverlayStartupTransitionContext? context,
        IEnumerable<Rect> revealTargets,
        double dpiScale)
    {
        var layer = new OverlayStartupTransitionLayer
        {
            _language = language,
            _context = context ?? OverlayStartupTransitionContext.Default,
            _pixelsPerDip = Math.Max(1, dpiScale)
        };
        layer.ApplyPalette(settings);
        layer.SetRevealTargets(revealTargets);

        var visual = new DrawingVisual();
        using (var drawingContext = visual.RenderOpen())
        {
            layer.DrawTerminalBoot(drawingContext, width, height, Clamp(progress, 0, 1));
        }

        var pixelWidth = Math.Max(1, (int)Math.Ceiling(width * dpiScale));
        var pixelHeight = Math.Max(1, (int)Math.Ceiling(height * dpiScale));
        var dpi = 96 * Math.Max(1, dpiScale);
        var bitmap = new RenderTargetBitmap(pixelWidth, pixelHeight, dpi, dpi, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);

        if ((!_isActive && !_isStaticSnapshot) || ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }

        var t = _isStaticSnapshot
            ? _staticSnapshotProgress
            : Clamp((DateTime.UtcNow - _startedAt).TotalMilliseconds / DurationMs, 0, 1);
        _pixelsPerDip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        DrawTerminalBoot(drawingContext, ActualWidth, ActualHeight, t);
    }

    private void CompositionTarget_Rendering(object? sender, EventArgs e)
    {
        var now = DateTime.UtcNow;
        var elapsed = (now - _startedAt).TotalMilliseconds;
        if (elapsed >= DurationMs)
        {
            Stop();
            return;
        }

        if (_lastInvalidatedAt != DateTime.MinValue &&
            (now - _lastInvalidatedAt).TotalMilliseconds < _targetFrameIntervalMs)
        {
            return;
        }

        _lastInvalidatedAt = now;
        InvalidateVisual();
    }

    private void DrawTerminalBoot(DrawingContext dc, double width, double height, double t)
    {
        var layerOpacity = TerminalLayerOpacity(t);
        if (layerOpacity <= 0.001)
        {
            return;
        }

        dc.PushOpacity(layerOpacity);
        DrawTerminalBackground(dc, width, height, t);
        DrawMatrixCanvas(dc, width, height, t);
        DrawFullscreenFrame(dc, width, height, t);
        DrawEdgeDiagnostics(dc, width, height, t);
        DrawGlobalReadouts(dc, width, height, t);
        DrawSystemMap(dc, width, height, t);
        DrawDiagnosticStrip(dc, width, height, t);
        DrawTerminalConsole(dc, width, height, t);
        DrawOverlayMountTargets(dc, width, height, t);
        DrawTerminalPulse(dc, width, height, t);
        DrawTerminalFlash(dc, width, height, t);
        DrawCompletionSweep(dc, width, height, t);
        DrawGlitches(dc, width, height, t);
        dc.Pop();
    }

    private void DrawTerminalBackground(DrawingContext dc, double width, double height, double t)
    {
        var rect = new Rect(0, 0, width, height);
        var takeover = SmoothStep(t / TakeoverEnd);
        var intensity = takeover * (0.62 + 0.38 * Math.Sin(Clamp(t / 0.82, 0, 1) * Math.PI));
        dc.DrawRectangle(BackgroundBrush(0.72 + 0.18 * takeover), null, rect);

        var glow = new RadialGradientBrush
        {
            Center = new Point(0.5, 0.48),
            GradientOrigin = new Point(0.5, 0.48),
            RadiusX = 0.62,
            RadiusY = 0.62
        };
        glow.GradientStops.Add(new GradientStop(PrimaryColor(0.22 * intensity), 0));
        glow.GradientStops.Add(new GradientStop(PrimaryColor(0.12 * intensity), 0.26));
        glow.GradientStops.Add(new GradientStop(PrimaryColor(0), 0.62));
        dc.DrawRectangle(glow, null, rect);

        var gridPen = new Pen(PrimaryBrush((0.03 + 0.09 * takeover + 0.04 * intensity) * (1 - SmoothStep((t - 0.92) / 0.08))), 1);
        for (var x = 0.5; x < width; x += 42)
        {
            dc.DrawLine(gridPen, new Point(x, 0), new Point(x, height));
        }

        for (var y = 0.5; y < height; y += 42)
        {
            dc.DrawLine(gridPen, new Point(0, y), new Point(width, y));
        }

        var vignette = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1)
        };
        vignette.GradientStops.Add(new GradientStop(Color.FromArgb(A(0.2), 0, 0, 0), 0));
        vignette.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0, 0, 0), 0.45));
        vignette.GradientStops.Add(new GradientStop(Color.FromArgb(A(0.36), 0, 0, 0), 1));
        dc.DrawRectangle(vignette, null, rect);
    }

    private void DrawMatrixCanvas(DrawingContext dc, double width, double height, double t)
    {
        var takeover = SmoothStep(t / TakeoverEnd);
        var finishFade = 1 - SmoothStep((t - FadeStart) / 0.12);
        var intensity = takeover * Math.Sin(Clamp(t / 0.9, 0, 1) * Math.PI) * finishFade;
        var scanProgress = Clamp(t / 0.24, 0, 1);
        var scanY = -height * 0.18 + height * 1.34 * scanProgress;
        var scanBrush = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1)
        };
        scanBrush.GradientStops.Add(new GradientStop(PrimaryColor(0), 0));
        scanBrush.GradientStops.Add(new GradientStop(PrimaryColor((0.08 + intensity * 0.24) * (1 - SmoothStep((t - 0.3) / 0.08))), 0.46));
        scanBrush.GradientStops.Add(new GradientStop(TextColor((0.05 + intensity * 0.14) * (1 - SmoothStep((t - 0.3) / 0.08))), 0.55));
        scanBrush.GradientStops.Add(new GradientStop(PrimaryColor(0), 1));
        dc.DrawRectangle(scanBrush, null, new Rect(0, scanY - 48, width, 112));

    }

    private void DrawFullscreenFrame(DrawingContext dc, double width, double height, double t)
    {
        var opacity = SmoothStep((t - 0.04) / 0.14) * (1 - SmoothStep((t - FadeStart) / 0.12));
        if (opacity <= 0.01)
        {
            return;
        }

        dc.PushOpacity(opacity);
        var inset = 24.0;
        var rect = new Rect(inset, inset, Math.Max(0, width - inset * 2), Math.Max(0, height - inset * 2));
        dc.DrawRectangle(null, new Pen(AccentBrush(0.36), 1), rect);
        DrawCorner(dc, rect.TopLeft, 96, 1, 1, SmoothStep((t - 0.04) / 0.11));
        DrawCorner(dc, rect.TopRight, 96, -1, 1, SmoothStep((t - 0.07) / 0.11));
        DrawCorner(dc, rect.BottomRight, 96, -1, -1, SmoothStep((t - 0.1) / 0.11));
        DrawCorner(dc, rect.BottomLeft, 96, 1, -1, SmoothStep((t - 0.13) / 0.11));

        var bandPen = new Pen(AccentBrush(0.56), 1);
        dc.DrawLine(bandPen, new Point(width * 0.13, rect.Top + 72), new Point(width * 0.87, rect.Top + 72));
        dc.DrawLine(bandPen, new Point(width * 0.13, rect.Bottom - 72), new Point(width * 0.87, rect.Bottom - 72));
        dc.Pop();
    }

    private void DrawCorner(DrawingContext dc, Point origin, double size, int xDir, int yDir, double progress)
    {
        progress = Clamp(progress, 0, 1);
        if (progress <= 0.01)
        {
            return;
        }

        var pen = new Pen(PrimaryBrush(0.86), 2);
        var horizontal = Clamp(progress * 1.65, 0, 1);
        var vertical = Clamp((progress - 0.36) * 1.65, 0, 1);
        dc.DrawLine(pen, origin, new Point(origin.X + size * xDir * horizontal, origin.Y));
        dc.DrawLine(pen, origin, new Point(origin.X, origin.Y + size * yDir * vertical));
    }

    private void DrawEdgeDiagnostics(DrawingContext dc, double width, double height, double t)
    {
        var opacity = SmoothStep((t - 0.06) / 0.18) * (1 - SmoothStep((t - FadeStart) / 0.12));
        if (opacity <= 0.01)
        {
            return;
        }

        dc.PushOpacity(opacity);
        var tickPen = new Pen(PrimaryBrush(0.24), 1);
        var hotPen = new Pen(AccentBrush(0.5), 1);
        for (var i = 0; i < 18; i++)
        {
            var x = 56 + i * Math.Max(42, (width - 112) / 17);
            var pulse = SmoothStep((t - (0.08 + i * 0.006)) / 0.08);
            var length = 8 + 12 * ((i % 3) == 0 ? 1 : 0);
            dc.DrawLine(i % 4 == 0 ? hotPen : tickPen, new Point(x, 28), new Point(x, 28 + length * pulse));
            dc.DrawLine(tickPen, new Point(x, height - 28), new Point(x, height - 28 - length * pulse));
        }

        for (var i = 0; i < 10; i++)
        {
            var y = 92 + i * Math.Max(48, (height - 184) / 9);
            var pulse = SmoothStep((t - (0.1 + i * 0.01)) / 0.08);
            dc.DrawLine(tickPen, new Point(28, y), new Point(28 + 16 * pulse, y));
            dc.DrawLine(i % 3 == 0 ? hotPen : tickPen, new Point(width - 28, y), new Point(width - 28 - 16 * pulse, y));
        }

        var blockOpacity = 0.16 + 0.12 * Math.Sin(t * Math.PI * 8);
        dc.DrawRectangle(PrimaryBrush(blockOpacity), null, new Rect(32, height * 0.5 - 42, 3, 84));
        dc.DrawRectangle(PrimaryBrush(blockOpacity), null, new Rect(width - 35, height * 0.5 - 42, 3, 84));
        DrawText(dc, _context.BottomLeftDiagnostic, 42, height - 54, 9, MutedBrush(0.72), MonoTypeface);
        DrawRightText(dc, _context.BottomRightDiagnostic, width - 42, height - 54, 9, MutedBrush(0.72), MonoTypeface);
        dc.Pop();
    }

    private void DrawGlobalReadouts(DrawingContext dc, double width, double height, double t)
    {
        var opacity = SmoothStep((t - 0.06) / 0.18) * (1 - SmoothStep((t - FadeStart) / 0.12));
        if (opacity <= 0.01)
        {
            return;
        }

        dc.PushOpacity(opacity);
        DrawTitleStrip(dc, width, t);

        var leftX = Math.Clamp(width * 0.04, 32, 72);
        var rightX = width - leftX - Math.Min(300, width * 0.21);
        var topY = height * 0.18;
        var cardWidth = Math.Min(300, width * 0.21);
        DrawReadoutCard(dc, new Rect(leftX, topY, cardWidth, 58), StatusSteps[0], 0, t);
        DrawReadoutCard(dc, new Rect(leftX, topY + 68, cardWidth, 58), StatusSteps[1], 1, t);
        DrawReadoutCard(dc, new Rect(leftX, topY + 136, cardWidth, 58), StatusSteps[2], 2, t);
        DrawReadoutCard(dc, new Rect(rightX, topY, cardWidth, 58), StatusSteps[3], 3, t);
        DrawReadoutCard(dc, new Rect(rightX, topY + 68, cardWidth, 58), StatusSteps[4], 4, t);
        DrawReadoutCard(dc, new Rect(rightX, topY + 136, cardWidth, 58), StatusSteps[5], 5, t);

        var bottomWidth = Math.Min(920, width - 96);
        var bottomX = (width - bottomWidth) / 2;
        var bottomY = height - 92;
        DrawReadoutCard(dc, new Rect(bottomX, bottomY, bottomWidth, 58), StatusSteps[6], 6, t);
        dc.Pop();
    }

    private void DrawTitleStrip(DrawingContext dc, double width, double t)
    {
        var stripWidth = Math.Min(980, width - 96);
        if (stripWidth <= 120)
        {
            return;
        }

        var open = SmoothStep((t - 0.06) / 0.16);
        var rect = new Rect((width - stripWidth * open) / 2, 32, stripWidth * open, 48);
        dc.DrawRectangle(BackgroundBrush(0.78), new Pen(AccentBrush(0.44), 1), rect);
        if (open < 0.82)
        {
            return;
        }

        var cy = rect.Top + 14;
        DrawText(dc, _context.HeaderTargetLabel, rect.Left + 18, cy + 4, 11, PrimaryBrush(0.9), MonoBoldTypeface);
        DrawCenteredText(dc, _context.SurfaceTitle, rect, cy, 17, TextBrush(0.98), MonoBoldTypeface);
        var state = t >= CompletionStart ? _context.OnlineStateLabel : t >= 0.38 ? _context.CheckingStateLabel : _context.MountingStateLabel;
        DrawRightText(dc, state, rect.Right - 18, cy + 4, 11, PrimaryBrush(0.9), MonoBoldTypeface);
    }

    private void DrawReadoutCard(DrawingContext dc, Rect rect, OverlayStartupStatusStep status, int index, double t)
    {
        var local = SmoothStep((t - (0.22 + index * 0.018)) / 0.11);
        if (local <= 0.01)
        {
            return;
        }

        var activation = StatusProgress(t, index);
        var pulse = StatusPulse(t, index);
        var state = activation >= 0.96 ? status.DoneState : status.PendingState;
        var accentAlpha = 0.16 + activation * 0.34 + pulse * 0.34;
        var stateBrush = activation >= 0.96
            ? SuccessBrush(0.76 + pulse * 0.22)
            : MutedBrush(0.76);

        dc.PushOpacity(local);
        var shifted = new Rect(rect.X + (1 - local) * 12, rect.Y, rect.Width, rect.Height);
        dc.DrawRoundedRectangle(BackgroundBrush(0.62), new Pen(AccentBrush(0.22 + accentAlpha * 0.5), 1), shifted, 5, 5);
        dc.DrawRectangle(PrimaryBrush(0.045 + activation * 0.055), null, new Rect(shifted.X, shifted.Y, shifted.Width, shifted.Height));
        dc.DrawRectangle(PrimaryBrush(0.12 + activation * 0.25), null, new Rect(shifted.X, shifted.Y, shifted.Width * activation, 2));
        DrawText(dc, status.Label, shifted.X + 12, shifted.Y + 9, 9, MutedBrush(0.95), MonoTypeface);
        DrawText(dc, status.Value, shifted.X + 12, shifted.Y + 30, 12, TextBrush(0.62 + activation * 0.33), MonoBoldTypeface, Math.Max(0, shifted.Width - 112));
        DrawRightText(dc, state, shifted.Right - 12, shifted.Y + 30, 12, stateBrush, MonoBoldTypeface);
        dc.DrawEllipse(stateBrush, null, new Point(shifted.Right - 18, shifted.Y + 17), 3.4 + pulse * 2, 3.4 + pulse * 2);
        DrawStatusCardSweep(dc, shifted, t, index);
        dc.Pop();
    }

    private void DrawStatusCardSweep(DrawingContext dc, Rect rect, double t, int index)
    {
        var local = Clamp((t - StatusStart(index)) / 0.11, 0, 1);
        if (local <= 0 || local >= 1)
        {
            return;
        }

        var opacity = Math.Sin(local * Math.PI);
        var x = rect.Left - rect.Width * 0.15 + rect.Width * 1.3 * local;
        var brush = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(1, 0)
        };
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 0));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0.42 * opacity), 0.45));
        brush.GradientStops.Add(new GradientStop(TextColor(0.52 * opacity), 0.54));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 1));
        dc.PushClip(new RectangleGeometry(rect));
        dc.DrawRectangle(brush, null, new Rect(x - 24, rect.Top, 58, rect.Height));
        dc.Pop();
    }

    private void DrawSystemMap(DrawingContext dc, double width, double height, double t)
    {
        var opacity = SmoothStep((t - 0.24) / 0.18) * (1 - SmoothStep((t - FadeStart) / 0.12));
        if (opacity <= 0.01)
        {
            return;
        }

        var size = Math.Min(520, width * 0.42);
        var cx = width / 2;
        var cy = height * 0.52;
        dc.PushOpacity(opacity * 0.76);
        var cyanPen = new Pen(PrimaryBrush(0.48), 1);
        var amberPen = new Pen(WarningBrush(0.4), 1);
        dc.DrawEllipse(null, cyanPen, new Point(cx, cy), size / 2, size / 2);
        dc.DrawEllipse(null, cyanPen, new Point(cx, cy), size * 0.36, size * 0.36);
        dc.DrawEllipse(null, amberPen, new Point(cx, cy), size * 0.22, size * 0.22);
        dc.DrawLine(cyanPen, new Point(cx, cy - size / 2), new Point(cx, cy + size / 2));
        dc.DrawLine(cyanPen, new Point(cx - size / 2, cy), new Point(cx + size / 2, cy));
        DrawMapNode(dc, cx - size * 0.22, cy - size * 0.16, SuccessBrush(1));
        DrawMapNode(dc, cx + size * 0.18, cy - size * 0.2, PrimaryBrush(1));
        DrawMapNode(dc, cx + size * 0.23, cy + size * 0.18, WarningBrush(1));
        DrawMapNode(dc, cx - size * 0.12, cy + size * 0.22, SuccessBrush(1));
        dc.Pop();
    }

    private static void DrawMapNode(DrawingContext dc, double x, double y, Brush brush)
    {
        dc.DrawEllipse(brush, null, new Point(x, y), 3.5, 3.5);
    }

    private void DrawDiagnosticStrip(DrawingContext dc, double width, double height, double t)
    {
        var opacity = SmoothStep((t - 0.32) / 0.18) * (1 - SmoothStep((t - FadeStart) / 0.12));
        if (opacity <= 0.01)
        {
            return;
        }

        var stripWidth = Math.Min(780, width - 120);
        var x = (width - stripWidth) / 2;
        var y = height / 2 + Math.Min(330, height * 0.32);
        var cell = (stripWidth - 17 * 5) / 18;
        dc.PushOpacity(opacity);
        for (var i = 0; i < 18; i++)
        {
            var statusIndex = Math.Min(StatusSteps.Count - 1, i / 3);
            var ready = StatusProgress(t, statusIndex);
            var pulse = 0.24 + 0.76 * Math.Sin((t * 3 + i * 0.11) * Math.PI);
            var alpha = 0.08 + ready * 0.22 + pulse * 0.13;
            dc.DrawRectangle(ready > 0.95 ? SuccessBrush(alpha) : PrimaryBrush(alpha), null, new Rect(x + i * (cell + 5), y, cell, 8));
        }
        dc.Pop();
    }

    private void DrawTerminalConsole(DrawingContext dc, double width, double height, double t)
    {
        var opacity = SmoothStep((t - ConsoleOpenStart) / 0.12) * (1 - SmoothStep((t - 0.9) / 0.08));
        if (opacity <= 0.01)
        {
            return;
        }

        var open = SmoothStep((t - ConsoleOpenStart) / 0.18);
        var collapse = SmoothStep((t - CompletionStart) / 0.1);
        var consoleWidth = Math.Min(780, width * 0.58) * (0.08 + open * 0.92);
        var fullHeight = Math.Min(360, height * 0.42);
        var consoleHeight = Math.Max(7, fullHeight * (0.04 + open * 0.96) * (1 - collapse) + 7 * collapse);
        var rect = new Rect((width - consoleWidth) / 2, height * 0.5 - consoleHeight / 2 + 20, consoleWidth, consoleHeight);
        dc.PushOpacity(opacity);
        dc.DrawRoundedRectangle(BackgroundBrush(0.84), new Pen(AccentBrush(0.46), 1.2), rect, 8, 8);
        dc.DrawRoundedRectangle(PrimaryBrush(0.045), null, rect, 8, 8);

        if (open > 0.74 && collapse < 0.82)
        {
            var topbar = new Rect(rect.X, rect.Y, rect.Width, 42);
            var contentOpacity = 1 - SmoothStep((collapse - 0.24) / 0.34);
            dc.PushClip(new RectangleGeometry(rect));
            if (contentOpacity > 0.01)
            {
                dc.PushOpacity(contentOpacity);
                dc.DrawRectangle(BackgroundBrush(0.72), null, topbar);
                dc.DrawLine(new Pen(AccentBrush(0.28), 1), new Point(rect.X, topbar.Bottom), new Point(rect.Right, topbar.Bottom));
                DrawWindowDots(dc, topbar.X + 16, topbar.Y + 17);
                DrawCenteredText(dc, _context.SurfaceTitle, topbar, topbar.Y + 13, 12, PrimaryBrush(0.95), MonoBoldTypeface);
                DrawRightText(dc, t >= CompletionStart ? _context.OnlineStateLabel : _context.BootStateLabel, topbar.Right - 16, topbar.Y + 14, 10, SuccessBrush(0.95), MonoBoldTypeface);
                DrawTerminalLines(dc, rect, t);
                DrawStatusChips(dc, rect, t);
                DrawConsoleProgress(dc, rect, t);
                DrawConsoleScan(dc, rect, t);
                DrawSmallCorners(dc, rect);
                dc.Pop();
            }

            if (collapse >= 0.58)
            {
                DrawConsoleCollapseLine(dc, rect, t);
            }

            dc.Pop();
        }
        else if (collapse >= 0.82)
        {
            DrawConsoleCollapseLine(dc, rect, t);
        }

        dc.Pop();
    }

    private void DrawConsoleCollapseLine(DrawingContext dc, Rect rect, double t)
    {
        var linePulse = 0.56 + 0.44 * Math.Sin(t * Math.PI * 28);
        dc.DrawRectangle(PrimaryBrush(0.22 + linePulse * 0.28), null, new Rect(rect.Left, rect.Top + rect.Height / 2 - 1, rect.Width, 2));
    }

    private void DrawOverlayMountTargets(DrawingContext dc, double width, double height, double t)
    {
        if (_revealTargets.Count == 0)
        {
            return;
        }

        var opacity = SmoothStep((t - 0.56) / 0.14) * (1 - SmoothStep((t - 0.94) / 0.06));
        if (opacity <= 0.01)
        {
            return;
        }

        var center = new Point(width / 2, height * 0.52);
        var linkPen = new Pen(PrimaryBrush(0.2 * opacity), 1);
        var borderPen = new Pen(AccentBrush(0.68 * opacity), 1.25);
        var hotPen = new Pen(TextBrush(0.72 * opacity), 1.6);

        for (var i = 0; i < _revealTargets.Count; i++)
        {
            var local = SmoothStep((t - (0.58 + i * 0.025)) / 0.14);
            if (local <= 0.01)
            {
                continue;
            }

            var rect = _revealTargets[i];
            rect.Inflate((1 - local) * 30, (1 - local) * 18);
            var scanY = CompletionSweepY(height, t);
            var swept = scanY >= rect.Top + rect.Height * 0.45;
            dc.PushOpacity(local);
            var targetCenter = new Point(rect.Left + rect.Width / 2, rect.Top + rect.Height / 2);
            dc.DrawLine(swept ? hotPen : linkPen, center, targetCenter);
            dc.DrawRectangle(PrimaryBrush((swept ? 0.07 : 0.045) * opacity), new Pen(PrimaryBrush((swept ? 0.42 : 0.26) * opacity), 1), rect);
            DrawMountCorners(dc, rect, Math.Min(46, Math.Max(20, rect.Width * 0.18)), swept ? hotPen : borderPen, hotPen);
            DrawMountScan(dc, rect, t, i, opacity);
            dc.Pop();
        }
    }

    private void DrawMountCorners(DrawingContext dc, Rect rect, double length, Pen borderPen, Pen hotPen)
    {
        dc.DrawLine(borderPen, rect.TopLeft, new Point(rect.Left + length, rect.Top));
        dc.DrawLine(borderPen, rect.TopLeft, new Point(rect.Left, rect.Top + length));
        dc.DrawLine(borderPen, rect.TopRight, new Point(rect.Right - length, rect.Top));
        dc.DrawLine(borderPen, rect.TopRight, new Point(rect.Right, rect.Top + length));
        dc.DrawLine(borderPen, rect.BottomLeft, new Point(rect.Left + length, rect.Bottom));
        dc.DrawLine(borderPen, rect.BottomLeft, new Point(rect.Left, rect.Bottom - length));
        dc.DrawLine(borderPen, rect.BottomRight, new Point(rect.Right - length, rect.Bottom));
        dc.DrawLine(borderPen, rect.BottomRight, new Point(rect.Right, rect.Bottom - length));

        var pip = 5.0;
        dc.DrawRectangle(hotPen.Brush, null, new Rect(rect.Left - pip / 2, rect.Top - pip / 2, pip, pip));
        dc.DrawRectangle(hotPen.Brush, null, new Rect(rect.Right - pip / 2, rect.Top - pip / 2, pip, pip));
        dc.DrawRectangle(hotPen.Brush, null, new Rect(rect.Right - pip / 2, rect.Bottom - pip / 2, pip, pip));
        dc.DrawRectangle(hotPen.Brush, null, new Rect(rect.Left - pip / 2, rect.Bottom - pip / 2, pip, pip));
    }

    private void DrawMountScan(DrawingContext dc, Rect rect, double t, int index, double opacity)
    {
        var scan = Clamp((t - (0.66 + index * 0.014)) / 0.2, 0, 1);
        if (scan <= 0 || scan >= 1)
        {
            return;
        }

        var x = rect.Left - rect.Width * 0.18 + rect.Width * 1.36 * scan;
        var brush = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(1, 0)
        };
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 0));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0.5 * opacity), 0.48));
        brush.GradientStops.Add(new GradientStop(TextColor(0.42 * opacity), 0.56));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 1));

        dc.PushClip(new RectangleGeometry(rect));
        dc.DrawRectangle(brush, null, new Rect(x - 18, rect.Top, 52, rect.Height));
        dc.DrawLine(new Pen(TextBrush(0.64 * opacity), 1), new Point(x, rect.Top), new Point(x, rect.Bottom));
        dc.Pop();
    }

    private void DrawWindowDots(DrawingContext dc, double x, double y)
    {
        dc.DrawEllipse(PrimaryBrush(0.78), null, new Point(x, y), 3.5, 3.5);
        dc.DrawEllipse(WarningBrush(0.82), null, new Point(x + 13, y), 3.5, 3.5);
        dc.DrawEllipse(SuccessBrush(0.82), null, new Point(x + 26, y), 3.5, 3.5);
    }

    private void DrawTerminalLines(DrawingContext dc, Rect rect, double t)
    {
        var x = rect.X + 18;
        var y = rect.Y + 60;
        var maxWidth = Math.Max(0, rect.Width - 270);
        var lineCount = Math.Min(8, TerminalLines.Count);
        for (var i = 0; i < lineCount; i++)
        {
            var start = 0.28 + i * 0.058 - Math.Max(0, i - 3) * 0.012;
            var duration = Math.Max(0.035, 0.08 - i * 0.005);
            var local = Clamp((t - start) / duration, 0, 1);
            if (local <= 0.01)
            {
                continue;
            }

            var line = TerminalLines[i];
            var visibleCharacters = Math.Max(1, (int)Math.Round(line.Length * SmoothStep(local)));
            var text = line[..Math.Min(visibleCharacters, line.Length)];
            if (local < 1)
            {
                text += "_";
            }

            dc.PushOpacity(SmoothStep(local));
            DrawText(dc, text, x, y + i * 23, Math.Clamp(rect.Width / 68, 10.5, 13), TextBrush(0.92), MonoTypeface, maxWidth);
            dc.Pop();
        }
    }

    private void DrawStatusChips(DrawingContext dc, Rect rect, double t)
    {
        var chipX = rect.Right - 238;
        var chipY = rect.Y + 60;
        for (var i = 0; i < StatusChipIndexes.Length; i++)
        {
            var statusIndex = StatusChipIndexes[i];
            var local = SmoothStep((t - (0.34 + i * 0.045)) / 0.12);
            if (local <= 0.01)
            {
                continue;
            }

            var progress = StatusProgress(t, statusIndex);
            var pulse = StatusPulse(t, statusIndex);
            var status = StatusSteps[statusIndex];
            var rectChip = new Rect(chipX + (1 - local) * 14, chipY + i * 64, 210, 54);
            dc.PushOpacity(local);
            dc.DrawRoundedRectangle(PrimaryBrush(0.04 + progress * 0.03), new Pen(AccentBrush(0.2 + progress * 0.22), 1), rectChip, 6, 6);
            DrawText(dc, status.Label.ToLowerInvariant(), rectChip.X + 10, rectChip.Y + 8, 9, MutedBrush(0.95), MonoTypeface);
            DrawText(dc, progress >= 0.96 ? status.DoneState : status.PendingState, rectChip.X + 10, rectChip.Y + 28, 12, TextBrush(0.7 + progress * 0.25), MonoBoldTypeface);
            dc.DrawEllipse(SuccessBrush(0.38 + progress * 0.54 + pulse * 0.08), null, new Point(rectChip.Right - 18, rectChip.Y + 34), 3.5 + pulse * 2, 3.5 + pulse * 2);
            dc.Pop();
        }
    }

    private void DrawConsoleProgress(DrawingContext dc, Rect rect, double t)
    {
        var completed = 0.0;
        for (var i = 0; i < StatusSteps.Count; i++)
        {
            completed += StatusProgress(t, i);
        }

        var progress = Clamp(completed / StatusSteps.Count, 0, 1);
        progress = Math.Max(progress, SmoothStep((t - 0.2) / 0.2) * 0.16);
        if (t >= CompletionStart)
        {
            progress = Math.Max(progress, 0.94 + SmoothStep((t - CompletionStart) / 0.06) * 0.06);
        }

        var track = new Rect(rect.X + 18, rect.Bottom - 24, Math.Max(0, rect.Width - 36), 6);
        dc.DrawRoundedRectangle(TextBrush(0.05), new Pen(AccentBrush(0.36), 1), track, 999, 999);
        dc.DrawRoundedRectangle(
            new LinearGradientBrush(_palette.Primary, _palette.Success, 0),
            null,
            new Rect(track.X, track.Y, track.Width * Clamp(progress, 0, 1), track.Height),
            999,
            999);
    }

    private void DrawConsoleScan(DrawingContext dc, Rect rect, double t)
    {
        var local = Clamp((t - 0.28) / 0.52, 0, 1);
        var opacity = Math.Sin(local * Math.PI);
        if (opacity <= 0.01)
        {
            return;
        }

        var y = rect.Y - rect.Height * 0.25 + rect.Height * 1.38 * local;
        var brush = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1)
        };
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 0));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0.28 * opacity), 0.48));
        brush.GradientStops.Add(new GradientStop(TextColor(0.12 * opacity), 0.58));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 1));
        dc.DrawRectangle(brush, null, new Rect(rect.X, y - 38, rect.Width, 82));
    }

    private void DrawSmallCorners(DrawingContext dc, Rect rect)
    {
        var inset = 14.0;
        var corner = new Rect(rect.X + inset, rect.Y + inset, rect.Width - inset * 2, rect.Height - inset * 2);
        var pen = new Pen(PrimaryBrush(0.72), 1);
        var len = 44.0;
        dc.DrawLine(pen, corner.TopLeft, new Point(corner.Left + len, corner.Top));
        dc.DrawLine(pen, corner.TopLeft, new Point(corner.Left, corner.Top + len));
        dc.DrawLine(pen, corner.TopRight, new Point(corner.Right - len, corner.Top));
        dc.DrawLine(pen, corner.TopRight, new Point(corner.Right, corner.Top + len));
        dc.DrawLine(pen, corner.BottomLeft, new Point(corner.Left + len, corner.Bottom));
        dc.DrawLine(pen, corner.BottomLeft, new Point(corner.Left, corner.Bottom - len));
        dc.DrawLine(pen, corner.BottomRight, new Point(corner.Right - len, corner.Bottom));
        dc.DrawLine(pen, corner.BottomRight, new Point(corner.Right, corner.Bottom - len));
    }

    private void DrawTerminalPulse(DrawingContext dc, double width, double height, double t)
    {
        var local = Clamp((t - 0.32) / 0.5, 0, 1);
        var completion = Math.Sin(Clamp((t - CompletionStart) / 0.1, 0, 1) * Math.PI) * 0.34;
        var opacity = Math.Sin(local * Math.PI) * 0.22 + completion;
        if (opacity <= 0.01)
        {
            return;
        }

        var scale = 0.42 + local * 1.36;
        var radius = 110 * scale;
        dc.DrawEllipse(null, new Pen(PrimaryBrush(opacity), 1), new Point(width / 2, height / 2), radius, radius);
    }

    private void DrawTerminalFlash(DrawingContext dc, double width, double height, double t)
    {
        var flash = 0.0;
        if (t >= CompletionStart && t <= CompletionStart + 0.035)
        {
            flash = SmoothStep((t - CompletionStart) / 0.035) * 0.58;
        }
        else if (t > CompletionStart + 0.035 && t <= CompletionStart + 0.08)
        {
            flash = (1 - SmoothStep((t - (CompletionStart + 0.035)) / 0.045)) * 0.58;
        }

        if (flash <= 0.01)
        {
            return;
        }

        var brush = new RadialGradientBrush
        {
            Center = new Point(0.5, 0.52),
            GradientOrigin = new Point(0.5, 0.52),
            RadiusX = 0.42,
            RadiusY = 0.38
        };
        brush.GradientStops.Add(new GradientStop(TextColor(0.82 * flash), 0));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0.36 * flash), 0.12));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0.1 * flash), 0.32));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 0.58));
        dc.DrawRectangle(brush, null, new Rect(0, 0, width, height));
    }

    private void DrawCompletionSweep(DrawingContext dc, double width, double height, double t)
    {
        var collapse = Clamp((t - CompletionStart) / 0.1, 0, 1);
        if (collapse > 0 && collapse < 1)
        {
            var expand = SmoothStep(collapse);
            var lineWidth = width * (0.18 + expand * 0.82);
            var y = height * 0.5 + 20;
            var x = (width - lineWidth) / 2;
            var glow = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0),
                EndPoint = new Point(1, 0)
            };
            glow.GradientStops.Add(new GradientStop(PrimaryColor(0), 0));
            glow.GradientStops.Add(new GradientStop(PrimaryColor(0.72), 0.44));
            glow.GradientStops.Add(new GradientStop(TextColor(0.86), 0.5));
            glow.GradientStops.Add(new GradientStop(PrimaryColor(0.72), 0.56));
            glow.GradientStops.Add(new GradientStop(PrimaryColor(0), 1));
            dc.DrawRectangle(glow, null, new Rect(x, y - 2, lineWidth, 4));
        }

        var sweep = Clamp((t - SweepStart) / 0.11, 0, 1);
        if (sweep <= 0)
        {
            return;
        }

        if (sweep < 1)
        {
            var ySweep = CompletionSweepY(height, t);
            var opacity = Math.Sin(sweep * Math.PI);
            var brush = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0),
                EndPoint = new Point(0, 1)
            };
            brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 0));
            brush.GradientStops.Add(new GradientStop(PrimaryColor(0.22 * opacity), 0.3));
            brush.GradientStops.Add(new GradientStop(TextColor(0.72 * opacity), 0.48));
            brush.GradientStops.Add(new GradientStop(PrimaryColor(0.36 * opacity), 0.56));
            brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 1));
            dc.DrawRectangle(brush, null, new Rect(0, ySweep - 42, width, 92));
        }

        var holdOpacity = CompletionHoldOpacity(t);
        if (holdOpacity <= 0.01)
        {
            return;
        }

        var labelY = height * 0.5 - 28;
        DrawCenteredText(dc, _context.CompletionLabel, new Rect(0, labelY, width, 24), labelY, 14, TextBrush(0.82 * holdOpacity), MonoBoldTypeface);
        if (!string.IsNullOrWhiteSpace(_context.CompletionSubLabel))
        {
            DrawCenteredText(dc, _context.CompletionSubLabel, new Rect(0, labelY + 21, width, 18), labelY + 21, 9.5, AccentBrush(0.58 * holdOpacity), MonoTypeface);
        }
    }

    private void DrawGlitches(DrawingContext dc, double width, double height, double t)
    {
        DrawGlitchLine(dc, width, height * 0.35, t, 0.58, 0.09);
        DrawGlitchLine(dc, width, height * 0.61, t, 0.63, 0.085);
    }

    private void DrawGlitchLine(DrawingContext dc, double width, double y, double t, double start, double span)
    {
        var local = Clamp((t - start) / span, 0, 1);
        var opacity = Math.Sin(local * Math.PI);
        if (opacity <= 0.01)
        {
            return;
        }

        var x0 = -width * 0.28 + width * 0.6 * local;
        var brush = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(1, 0)
        };
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 0));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0.95 * opacity), 0.45));
        brush.GradientStops.Add(new GradientStop(TextColor(0.8 * opacity), 0.55));
        brush.GradientStops.Add(new GradientStop(PrimaryColor(0), 1));
        dc.DrawRectangle(brush, null, new Rect(x0, y, width * 1.3, 2));
    }

    private void DrawText(DrawingContext dc, string text, double x, double y, double size, Brush brush, Typeface typeface, double? maxWidth = null)
    {
        var formatted = new FormattedText(
            text,
            CultureInfo.CurrentUICulture,
            WpfFlowDirection.LeftToRight,
            typeface,
            size,
            brush,
            _pixelsPerDip);

        if (maxWidth is > 0)
        {
            formatted.MaxTextWidth = maxWidth.Value;
        }

        dc.DrawText(formatted, new Point(x, y));
    }

    private void DrawCenteredText(DrawingContext dc, string text, Rect rect, double y, double size, Brush brush, Typeface typeface)
    {
        var formatted = new FormattedText(
            text,
            CultureInfo.CurrentUICulture,
            WpfFlowDirection.LeftToRight,
            typeface,
            size,
            brush,
            _pixelsPerDip);
        dc.DrawText(formatted, new Point(rect.Left + (rect.Width - formatted.Width) / 2, y));
    }

    private void DrawRightText(DrawingContext dc, string text, double right, double y, double size, Brush brush, Typeface typeface)
    {
        var formatted = new FormattedText(
            text,
            CultureInfo.CurrentUICulture,
            WpfFlowDirection.LeftToRight,
            typeface,
            size,
            brush,
            _pixelsPerDip);
        dc.DrawText(formatted, new Point(right - formatted.Width, y));
    }

    private static double TerminalLayerOpacity(double t)
    {
        if (t < 0.05)
        {
            return t / 0.05;
        }

        if (t < FadeStart)
        {
            return 1;
        }

        return 1 - Clamp((t - FadeStart) / 0.12, 0, 1);
    }

    private static double CompletionHoldOpacity(double t)
    {
        var sweepDone = SweepStart + 0.1;
        if (t < sweepDone)
        {
            return SmoothStep((t - SweepStart) / 0.1) * 0.76;
        }

        if (t < 0.94)
        {
            return 0.92;
        }

        return 0.92 * (1 - SmoothStep((t - 0.94) / 0.06));
    }

    private static double StatusStart(int index)
    {
        return 0.39 + index * 0.048;
    }

    private static double StatusProgress(double t, int index)
    {
        return SmoothStep((t - StatusStart(index)) / 0.065);
    }

    private static double StatusPulse(double t, int index)
    {
        var local = Clamp((t - StatusStart(index)) / 0.12, 0, 1);
        return Math.Sin(local * Math.PI);
    }

    private static double CompletionSweepY(double height, double t)
    {
        var sweep = Clamp((t - SweepStart) / 0.11, 0, 1);
        return -height * 0.12 + height * 1.24 * SmoothStep(sweep);
    }

    private static double SmoothStep(double t)
    {
        t = Clamp(t, 0, 1);
        return t * t * (3 - 2 * t);
    }

    private static double Clamp(double value, double min, double max)
    {
        return Math.Max(min, Math.Min(max, value));
    }

    private static double Distance(double x1, double y1, double x2, double y2)
    {
        var dx = x1 - x2;
        var dy = y1 - y2;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    private SolidColorBrush BackgroundBrush(double alpha)
    {
        return PaletteBrush(_palette.Background, alpha);
    }

    private SolidColorBrush PrimaryBrush(double alpha)
    {
        return PaletteBrush(_palette.Primary, alpha);
    }

    private SolidColorBrush AccentBrush(double alpha)
    {
        return PaletteBrush(_palette.Accent, alpha);
    }

    private SolidColorBrush TextBrush(double alpha)
    {
        return PaletteBrush(_palette.Text, alpha);
    }

    private SolidColorBrush MutedBrush(double alpha)
    {
        return PaletteBrush(_palette.Muted, alpha);
    }

    private SolidColorBrush SuccessBrush(double alpha)
    {
        return PaletteBrush(_palette.Success, alpha);
    }

    private SolidColorBrush WarningBrush(double alpha)
    {
        return PaletteBrush(_palette.Warning, alpha);
    }

    private Color PrimaryColor(double alpha)
    {
        return PaletteColor(_palette.Primary, alpha);
    }

    private Color AccentColor(double alpha)
    {
        return PaletteColor(_palette.Accent, alpha);
    }

    private Color TextColor(double alpha)
    {
        return PaletteColor(_palette.Text, alpha);
    }

    private Color SuccessColor(double alpha)
    {
        return PaletteColor(_palette.Success, alpha);
    }

    private Color WarningColor(double alpha)
    {
        return PaletteColor(_palette.Warning, alpha);
    }

    private bool ApplyPalette(OverlayDisplaySettings settings)
    {
        var nextPalette = TerminalTransitionPalette.FromSettings(settings);
        if (_palette.Equals(nextPalette))
        {
            return false;
        }

        _palette = nextPalette;
        _brushCache.Clear();
        return true;
    }

    private void ApplyFrameRate(OverlayDisplaySettings settings)
    {
        _targetFrameIntervalMs = GetTargetFrameIntervalMs(settings.StartupTransitionFrameRate);
    }

    private static double GetTargetFrameIntervalMs(OverlayStartupTransitionFrameRate frameRate)
    {
        return 1000.0 / Math.Clamp((int)frameRate, 30, 120);
    }

    private SolidColorBrush PaletteBrush(Color color, double alpha)
    {
        var alphaByte = A(alpha);
        var key = ((uint)alphaByte << 24) |
                  ((uint)color.R << 16) |
                  ((uint)color.G << 8) |
                  color.B;

        if (_brushCache.TryGetValue(key, out var brush))
        {
            return brush;
        }

        brush = new SolidColorBrush(Color.FromArgb(alphaByte, color.R, color.G, color.B));
        brush.Freeze();
        _brushCache[key] = brush;
        return brush;
    }

    private static Color PaletteColor(Color color, double alpha)
    {
        return Color.FromArgb(A(alpha), color.R, color.G, color.B);
    }

    private static byte A(double alpha)
    {
        return (byte)Math.Round(Clamp(alpha, 0, 1) * 255);
    }

    private readonly record struct TerminalTransitionPalette(
        Color Background,
        Color Primary,
        Color Accent,
        Color Text,
        Color Muted,
        Color Success,
        Color Warning)
    {
        public static TerminalTransitionPalette Default { get; } = new(
            Color.FromRgb(2, 8, 13),
            Color.FromRgb(85, 215, 255),
            Color.FromRgb(123, 226, 255),
            Color.FromRgb(237, 251, 255),
            Color.FromRgb(137, 168, 184),
            Color.FromRgb(114, 255, 182),
            Color.FromRgb(255, 209, 102));

        public static TerminalTransitionPalette FromSettings(OverlayDisplaySettings settings)
        {
            if (!settings.StartupTransitionFollowOverlayTheme)
            {
                return Default;
            }

            return settings.Theme switch
            {
                OverlayVisualTheme.Anvil => new(
                    Color.FromRgb(0, 18, 14),
                    Color.FromRgb(0, 255, 141),
                    Color.FromRgb(78, 255, 171),
                    Color.FromRgb(229, 255, 242),
                    Color.FromRgb(120, 221, 173),
                    Color.FromRgb(121, 255, 92),
                    Color.FromRgb(208, 255, 0)),
                OverlayVisualTheme.Drake => new(
                    Color.FromRgb(22, 10, 0),
                    Color.FromRgb(255, 138, 18),
                    Color.FromRgb(255, 178, 48),
                    Color.FromRgb(255, 236, 196),
                    Color.FromRgb(230, 151, 62),
                    Color.FromRgb(255, 190, 52),
                    Color.FromRgb(255, 222, 89)),
                OverlayVisualTheme.Argo => new(
                    Color.FromRgb(23, 12, 3),
                    Color.FromRgb(255, 111, 55),
                    Color.FromRgb(255, 132, 73),
                    Color.FromRgb(255, 235, 211),
                    Color.FromRgb(255, 167, 113),
                    Color.FromRgb(125, 255, 126),
                    Color.FromRgb(142, 255, 116)),
                OverlayVisualTheme.Musashi => new(
                    Color.FromRgb(20, 17, 5),
                    Color.FromRgb(255, 212, 98),
                    Color.FromRgb(255, 228, 128),
                    Color.FromRgb(255, 246, 214),
                    Color.FromRgb(131, 242, 221),
                    Color.FromRgb(94, 255, 225),
                    Color.FromRgb(91, 255, 230)),
                OverlayVisualTheme.Mirai => new(
                    Color.FromRgb(5, 20, 30),
                    Color.FromRgb(83, 196, 255),
                    Color.FromRgb(134, 225, 255),
                    Color.FromRgb(235, 250, 255),
                    Color.FromRgb(122, 191, 220),
                    Color.FromRgb(105, 255, 218),
                    Color.FromRgb(255, 92, 72)),
                OverlayVisualTheme.Crusader => new(
                    Color.FromRgb(4, 16, 34),
                    Color.FromRgb(20, 145, 255),
                    Color.FromRgb(110, 205, 255),
                    Color.FromRgb(240, 250, 255),
                    Color.FromRgb(146, 202, 255),
                    Color.FromRgb(97, 255, 126),
                    Color.FromRgb(84, 255, 107)),
                OverlayVisualTheme.Aegis => new(
                    Color.FromRgb(0, 18, 16),
                    Color.FromRgb(55, 224, 214),
                    Color.FromRgb(84, 245, 232),
                    Color.FromRgb(224, 255, 250),
                    Color.FromRgb(112, 201, 193),
                    Color.FromRgb(92, 255, 185),
                    Color.FromRgb(255, 51, 41)),
                OverlayVisualTheme.Rsi => new(
                    Color.FromRgb(20, 12, 34),
                    Color.FromRgb(150, 143, 255),
                    Color.FromRgb(214, 201, 255),
                    Color.FromRgb(250, 246, 255),
                    Color.FromRgb(187, 166, 220),
                    Color.FromRgb(116, 238, 210),
                    Color.FromRgb(255, 151, 58)),
                OverlayVisualTheme.Origin => new(
                    Color.FromRgb(7, 17, 28),
                    Color.FromRgb(88, 170, 255),
                    Color.FromRgb(176, 219, 255),
                    Color.FromRgb(245, 250, 255),
                    Color.FromRgb(132, 185, 232),
                    Color.FromRgb(135, 255, 180),
                    Color.FromRgb(255, 96, 83)),
                OverlayVisualTheme.Aopoa => new(
                    Color.FromRgb(4, 28, 30),
                    Color.FromRgb(77, 255, 225),
                    Color.FromRgb(126, 255, 237),
                    Color.FromRgb(230, 255, 250),
                    Color.FromRgb(116, 211, 198),
                    Color.FromRgb(156, 255, 77),
                    Color.FromRgb(171, 255, 67)),
                OverlayVisualTheme.Esperia => new(
                    Color.FromRgb(30, 6, 20),
                    Color.FromRgb(255, 60, 78),
                    Color.FromRgb(255, 92, 112),
                    Color.FromRgb(255, 228, 236),
                    Color.FromRgb(211, 125, 162),
                    Color.FromRgb(255, 108, 128),
                    Color.FromRgb(168, 77, 255)),
                OverlayVisualTheme.Gatac => new(
                    Color.FromRgb(24, 10, 32),
                    Color.FromRgb(255, 176, 210),
                    Color.FromRgb(255, 205, 230),
                    Color.FromRgb(255, 238, 246),
                    Color.FromRgb(203, 147, 221),
                    Color.FromRgb(255, 190, 230),
                    Color.FromRgb(255, 122, 76)),
                OverlayVisualTheme.NightShadow => new(
                    Color.FromRgb(3, 5, 8),
                    Color.FromRgb(214, 31, 53),
                    Color.FromRgb(255, 54, 74),
                    Color.FromRgb(232, 237, 242),
                    Color.FromRgb(135, 145, 156),
                    Color.FromRgb(238, 238, 242),
                    Color.FromRgb(255, 54, 74)),
                _ => Default
            };
        }
    }

}
