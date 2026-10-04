using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Threading;

namespace StarBridge.Desktop.Tests;

// Own offscreen, synthetic window only. No product HWND is moved or closed.
internal sealed class MenuZOrderFixture : IDisposable
{
    private readonly Thread _thread;
    private readonly TaskCompletionSource<(Dispatcher Dispatcher, HwndSource Source)> _ready = new();
    private readonly Dispatcher _dispatcher;
    private readonly HwndSource _source;
    internal IntPtr Handle { get; }

    internal MenuZOrderFixture()
    {
        _thread = new Thread(() =>
        {
            var source = new HwndSource(new HwndSourceParameters("Synthetic menu stacking fixture")
            {
                PositionX = -30000, PositionY = -30000, Width = 800, Height = 600,
                WindowStyle = unchecked((int)0x90000000), // WS_POPUP | WS_VISIBLE
                ExtendedWindowStyle = 0x08000008 // NOACTIVATE | TOPMOST
            });
            _ready.SetResult((Dispatcher.CurrentDispatcher, source));
            Dispatcher.Run();
        });
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        (_dispatcher, _source) = _ready.Task.GetAwaiter().GetResult();
        Handle = _source.Handle;
    }

    internal async Task AssertAbove(IntPtr hud)
    {
        for (var attempt = 0; attempt < 30; attempt++)
        {
            for (var next = GetWindow(Handle, 2); next != IntPtr.Zero; next = GetWindow(next, 2))
                if (next == hud) return;
            await Task.Delay(20);
        }
        throw new InvalidOperationException("visible menu must remain above real HUD HWND");
    }

    internal void TryPromote(IntPtr hud) =>
        SetWindowPos(hud, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);

    public void Dispose()
    {
        _dispatcher.Invoke(() => { _source.Dispose(); _dispatcher.InvokeShutdown(); });
        _thread.Join();
    }

    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr handle, uint command);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr handle, IntPtr after,
        int x, int y, int width, int height, uint flags);
}
