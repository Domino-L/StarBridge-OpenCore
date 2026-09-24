using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.HostRuntime.Communities;
using Forms = System.Windows.Forms;

namespace StarBridge.OverlayRuntime.Windows;

/// <summary>Windows-only image selection/encoding. No WPF page or crop window is opened.</summary>
public sealed class WindowsCommunityLogoPicker(int parentProcessId) : ICommunityLogoPicker
{
    private readonly object _gate = new();
    private BitmapSource? _original;
    private string? _sourceRef;
    private long _revision;
    private bool _disposed;

    public Task<CommunityLogoSource?> PickAsync(CancellationToken token)
    {
        long revision;
        lock (_gate) { ObjectDisposedException.ThrowIf(_disposed, this); revision = ++_revision; _original = null; _sourceRef = null; }
        var completion = new TaskCompletionSource<CommunityLogoSource?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                token.ThrowIfCancellationRequested();
                using var parent = Process.GetProcessById(parentProcessId);
                var owner = parent.MainWindowHandle;
                if (owner == IntPtr.Zero || !IsWindow(owner)) throw new InvalidOperationException("Owner unavailable.");
                using var dialog = new Forms.OpenFileDialog
                {
                    Filter = "Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp",
                    CheckFileExists = true, Multiselect = false, RestoreDirectory = true,
                };
                var threadId = GetCurrentThreadId();
                void ClosePicker() => EnumThreadWindows(threadId, (window, _) => { PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero); return true; }, IntPtr.Zero);
                using var cancellation = token.Register(ClosePicker);
                // Covers cancellation between the initial token check and native dialog creation.
                using var timer = new Forms.Timer { Interval = 100 };
                timer.Tick += (_, _) => { if (token.IsCancellationRequested) ClosePicker(); };
                timer.Start();
                if (dialog.ShowDialog(new WindowOwner(owner)) != Forms.DialogResult.OK)
                {
                    token.ThrowIfCancellationRequested();
                    completion.TrySetResult(null);
                    return;
                }
                token.ThrowIfCancellationRequested();
                // Only the path just chosen by this native dialog may be opened. No path enters Bridge.
                using var input = dialog.OpenFile();
                var retained = WindowsCommunityLogoImage.Load(input);
                var preview = WindowsCommunityLogoImage.Preview(retained);
                token.ThrowIfCancellationRequested();
                lock (_gate)
                {
                    if (_disposed || revision != _revision) throw new OperationCanceledException(token);
                    _original = retained;
                    _sourceRef = Guid.NewGuid().ToString("N");
                    completion.TrySetResult(new(_sourceRef, preview, retained.PixelWidth, retained.PixelHeight));
                }
            }
            catch (OperationCanceledException) { completion.TrySetCanceled(token.IsCancellationRequested ? token : new CancellationToken(true)); }
            catch (Exception)
            { completion.TrySetException(new InvalidDataException("The selected image cannot be used.")); }
        }) { IsBackground = true, Name = "StarBridge organization image picker" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return completion.Task;
    }

    public string Crop(string sourceRef, double x, double y, double size)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var image = _original;
            if (image is null || sourceRef != _sourceRef) throw new InvalidDataException();
            return WindowsCommunityLogoImage.Crop(image, x, y, size);
        }
    }

    public void Clear() { lock (_gate) { _revision++; _original = null; _sourceRef = null; } }
    public string CropAvatar(string sourceRef, double x, double y, double size)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var image = _original;
            if (image is null || sourceRef != _sourceRef) throw new InvalidDataException();
            // Match the smallest avatar display budget (chat/room), not the logo budget.
            return WindowsCommunityLogoImage.Crop(image, x, y, size, 90 * 1024, 256);
        }
    }
    public void Dispose() { lock (_gate) { Clear(); _disposed = true; } }
    private sealed class WindowOwner(IntPtr handle) : Forms.IWin32Window { public IntPtr Handle => handle; }
    private delegate bool EnumThreadDelegate(IntPtr window, IntPtr parameter);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool EnumThreadWindows(uint threadId, EnumThreadDelegate callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr window);
}
