namespace StarBridge.Desktop.FlutterHost;

using System.Windows;
using System.Windows.Threading;

internal sealed class WpfDesktopUiSurface(Window window) : IDesktopUiSurface
{
    private readonly Window _window = window ?? throw new ArgumentNullException(nameof(window));

    public ValueTask HideAsync(CancellationToken cancellationToken = default) =>
        InvokeAsync(() =>
        {
            _window.Hide();
            _window.ShowInTaskbar = false;
        }, cancellationToken);

    public ValueTask ShowAsync(CancellationToken cancellationToken = default) =>
        InvokeAsync(() =>
        {
            _window.ShowInTaskbar = true;
            if (!_window.IsVisible)
            {
                _window.Show();
            }

            if (_window.WindowState == WindowState.Minimized)
            {
                _window.WindowState = WindowState.Normal;
            }

            MainWindowPlacementService.EnsureVisible(_window);
            ActivateWindow();
        }, cancellationToken);

    public ValueTask ActivateAsync(CancellationToken cancellationToken = default) =>
        InvokeAsync(() =>
        {
            _window.ShowInTaskbar = true;
            if (!_window.IsVisible)
            {
                _window.Show();
            }

            if (_window.WindowState == WindowState.Minimized)
            {
                _window.WindowState = WindowState.Normal;
            }

            MainWindowPlacementService.EnsureVisible(_window);
            ActivateWindow();
        }, cancellationToken);

    private void ActivateWindow()
    {
        _window.Activate();
        _window.Topmost = true;
        _window.Topmost = false;
        _window.Focus();
    }

    private ValueTask InvokeAsync(Action action, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (_window.Dispatcher.CheckAccess())
        {
            action();
            return ValueTask.CompletedTask;
        }

        var operation = _window.Dispatcher.InvokeAsync(
            action,
            DispatcherPriority.Send,
            cancellationToken);
        return new ValueTask(operation.Task);
    }
}
