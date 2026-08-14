using System.Windows;
using System.Windows.Threading;

namespace StarBridge.Desktop;

internal interface IInGameScreenshotVisibilityGuard
{
    void BeginScreenshotVisibilitySuppression();
    void EndScreenshotVisibilitySuppression();
}

internal static class InGameScreenshotCaptureSession
{
    private static readonly TimeSpan DefaultCompositionSettleDelay =
        TimeSpan.FromMilliseconds(120);

    internal static async Task<T> RunAsync<T>(
        IEnumerable<Window> sessionWindows,
        Dispatcher dispatcher,
        Func<Task<T>> capture,
        TimeSpan? compositionSettleDelay = null)
    {
        ArgumentNullException.ThrowIfNull(sessionWindows);
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(capture);

        Window[] windows = [];
        IInGameScreenshotVisibilityGuard[] visibilityGuards = [];
        try
        {
            await dispatcher.InvokeAsync(
                () =>
                {
                    var allWindows = sessionWindows
                        .Distinct()
                        .ToArray();
                    windows = allWindows
                        .Where(static window => window.IsVisible)
                        .ToArray();
                    visibilityGuards = allWindows
                        .OfType<IInGameScreenshotVisibilityGuard>()
                        .ToArray();
                    foreach (var guard in visibilityGuards)
                    {
                        guard.BeginScreenshotVisibilitySuppression();
                    }

                    foreach (var window in windows)
                    {
                        window.Hide();
                    }
                },
                DispatcherPriority.Render);
            var settleDelay = compositionSettleDelay ??
                DefaultCompositionSettleDelay;
            if (settleDelay > TimeSpan.Zero)
            {
                await Task.Delay(settleDelay);
            }

            return await capture();
        }
        finally
        {
            await dispatcher.InvokeAsync(() =>
            {
                try
                {
                    foreach (var window in windows)
                    {
                        if (window.IsLoaded && !window.IsVisible)
                        {
                            window.Show();
                        }
                    }
                }
                finally
                {
                    foreach (var guard in visibilityGuards)
                    {
                        guard.EndScreenshotVisibilitySuppression();
                    }
                }
            });
        }
    }
}
