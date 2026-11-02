namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime : IInformationOverlayAppearancePreviewRuntime
{
    private IDisposable? _appearancePreview;
    private string? _appearancePreviewSession;
    private DispatcherTimer? _appearancePreviewExpiry;
    internal System.Windows.Rect? TestAppearancePreviewBounds;

    public IReadOnlyList<string> GetLivePreviewAppearanceIds()
    {
        if (_disposed) return [];
        List<string> ids = [];
        CollectExtendedLivePreviewIds(ids);
        if (ids.Count > 8 || ids.Distinct(StringComparer.Ordinal).Count() != ids.Count) return [];
        return ids.Where(id => OverlaySkinCatalog.Listed.Any(p => p.Id.ToString() == id && p.IsPreviewAvailable)).ToArray();
    }

    public async ValueTask<string?> OpenAppearancePreviewAsync(string appearanceId,
        OverlayAppearanceOptions options, bool reduceMotion = false, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(options);
        cancellationToken.ThrowIfCancellationRequested();
        if (!GetLivePreviewAppearanceIds().Contains(appearanceId, StringComparer.Ordinal)) return null;
        var dispatcher = PreviewDispatcher();
        var session = await dispatcher.InvokeAsync(() =>
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            cancellationToken.ThrowIfCancellationRequested();
            CloseAppearancePreviewCore();
            IDisposable? candidate = null;
            try
            {
                CreateExtendedAppearancePreview(appearanceId, options, reduceMotion, ref candidate);
                cancellationToken.ThrowIfCancellationRequested();
                if (candidate is null) return null;
                _appearancePreview = candidate;
                _appearancePreviewSession = Guid.NewGuid().ToString("N");
                // A lost bridge connection cannot leave an unbounded preview running.
                _appearancePreviewExpiry = new DispatcherTimer { Interval = TimeSpan.FromMinutes(10) };
                _appearancePreviewExpiry.Tick += (_, _) => CloseAppearancePreviewCore();
                _appearancePreviewExpiry.Start();
                return _appearancePreviewSession;
            }
            catch { candidate?.Dispose(); throw; }
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
        if (cancellationToken.IsCancellationRequested)
        {
            if (session is not null) await CloseAppearancePreviewAsync(session).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
        }
        return session;
    }

    public async ValueTask CloseAppearancePreviewAsync(string sessionId, CancellationToken cancellationToken = default)
    {
        if (!Guid.TryParseExact(sessionId, "N", out _)) return;
        var dispatcher = PreviewDispatcher();
        await dispatcher.InvokeAsync(() =>
        {
            if (string.Equals(sessionId, _appearancePreviewSession, StringComparison.Ordinal)) CloseAppearancePreviewCore();
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }

    private Dispatcher PreviewDispatcher()
    {
        lock (_lifetimeLock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_dispatcher is null || _dispatcher.HasShutdownStarted || _dispatcher.HasShutdownFinished)
                throw new InvalidOperationException("Native preview is unavailable.");
            return _dispatcher;
        }
    }

    private void CloseAppearancePreviewCore()
    {
        _appearancePreviewExpiry?.Stop();
        _appearancePreviewExpiry = null;
        var preview = _appearancePreview;
        _appearancePreview = null;
        _appearancePreviewSession = null;
        preview?.Dispose();
    }

    partial void CollectExtendedLivePreviewIds(List<string> ids);
    partial void CreateExtendedAppearancePreview(string appearanceId, OverlayAppearanceOptions options, bool reduceMotion, ref IDisposable? preview);
}
