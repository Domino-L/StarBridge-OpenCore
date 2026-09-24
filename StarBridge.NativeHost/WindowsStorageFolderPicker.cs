using System.Runtime.InteropServices;
using System.Text;

namespace StarBridge.NativeHost;

internal sealed class WindowsStorageFolderPicker(Func<nint> owner)
{
    internal Task<string?> ChooseAsync(CancellationToken cancellation)
    {
        var completion = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try { completion.TrySetResult(Choose(cancellation)); }
            catch (OperationCanceledException) { completion.TrySetCanceled(cancellation); }
            catch (Exception error) { completion.TrySetException(error); }
        }) { IsBackground = true, Name = "StarBridge storage folder picker" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return completion.Task;
    }

    private string? Choose(CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        var window = owner();
        if (window == 0 || !IsWindow(window)) throw new InvalidOperationException();
        Marshal.ThrowExceptionForHR(CoInitializeEx(0, 2)); // STA required by the Shell picker.
        nint dialog = 0;
        Callback callback = (handle, message, _, _) => {
            if (message == 1) {
                Interlocked.Exchange(ref dialog, handle);
                if (cancellation.IsCancellationRequested) PostMessage(handle, 0x10, 0, 0);
            }
            return 0;
        };
        using var registration = cancellation.Register(() => {
            var handle = Interlocked.CompareExchange(ref dialog, 0, 0);
            if (handle != 0) PostMessage(handle, 0x10, 0, 0);
        });
        nint item = 0;
        nint display = 0;
        try
        {
            // BROWSEINFOW owns no storage: pszDisplayName is a writable MAX_PATH
            // buffer. StringBuilder cannot be marshalled as a structure field.
            display = Marshal.AllocCoTaskMem(260 * sizeof(char));
            Marshal.WriteInt16(display, 0);
            var options = new BrowseInfo { Owner = window, Display = display,
                Flags = 0x41, Callback = callback };
            item = SHBrowseForFolder(ref options);
            cancellation.ThrowIfCancellationRequested();
            if (item == 0) return null;
            var path = new StringBuilder(32768);
            if (!SHGetPathFromIDListEx(item, path, (uint)path.Capacity, 0)) throw new IOException();
            return path.ToString();
        }
        finally
        {
            Interlocked.Exchange(ref dialog, 0);
            if (item != 0) Marshal.FreeCoTaskMem(item);
            if (display != 0) Marshal.FreeCoTaskMem(display);
            CoUninitialize();
            GC.KeepAlive(callback);
        }
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)] private delegate int Callback(nint window, uint message, nint lParam, nint data);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct BrowseInfo { public nint Owner, Root, Display; public string? Title;
        public uint Flags; public Callback Callback; public nint Data; public int Image; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHBrowseForFolderW")] private static extern nint SHBrowseForFolder(ref BrowseInfo info);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SHGetPathFromIDListEx(nint item, StringBuilder path, uint length, uint flags);
    [DllImport("ole32.dll")] private static extern int CoInitializeEx(nint reserved, uint mode);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool IsWindow(nint window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "PostMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
}
