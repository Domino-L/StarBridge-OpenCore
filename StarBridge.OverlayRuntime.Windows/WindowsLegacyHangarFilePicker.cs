using System.Diagnostics;
using System.Runtime.InteropServices;
using StarBridge.HostRuntime.Hangar;
using Forms = System.Windows.Forms;

namespace StarBridge.OverlayRuntime.Windows;

// Native file selection only. No content reads or filename-based ownership inference.
public sealed class WindowsLegacyHangarFilePicker(int parentProcessId) : ILegacyHangarFilePicker
{
    public Task<string?> PickAsync(string locale, CancellationToken token)
    {
        var completion = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                token.ThrowIfCancellationRequested();
                using var parent = Process.GetProcessById(parentProcessId);
                var owner = parent.MainWindowHandle;
                if (owner == 0 || !IsWindow(owner)) throw new InvalidOperationException();
                using var dialog = new Forms.OpenFileDialog {
                    Filter = "StarBridge (*.database)|*.database", CheckFileExists = true,
                    Multiselect = false, RestoreDirectory = true,
                    Title = locale switch {
                        "en" => "Select an old hangar file",
                        "zh-TW" => "選擇舊版機庫檔案",
                        _ => "选择旧版机库文件"
                    }
                };
                var threadId = GetCurrentThreadId();
                void Close() => EnumThreadWindows(threadId, (window, _) => {
                    PostMessage(window, 0x0010, 0, 0); return true;
                }, 0);
                using var cancellation = token.Register(Close);
                using var timer = new Forms.Timer { Interval = 100 };
                timer.Tick += (_, _) => { if (token.IsCancellationRequested) Close(); };
                timer.Start();
                var selected = dialog.ShowDialog(new Owner(owner)) == Forms.DialogResult.OK;
                token.ThrowIfCancellationRequested();
                completion.TrySetResult(selected ? dialog.FileName : null);
            }
            catch (OperationCanceledException) { completion.TrySetCanceled(token); }
            catch (Exception) { completion.TrySetException(new InvalidOperationException("File selection unavailable.")); }
        }) { IsBackground = true, Name = "StarBridge old hangar file selection" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return completion.Task;
    }
    private sealed class Owner(nint handle) : Forms.IWin32Window { public nint Handle => handle; }
    private delegate bool EnumThreadDelegate(nint window, nint parameter);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool EnumThreadWindows(uint thread, EnumThreadDelegate callback, nint parameter);
    [DllImport("user32.dll")] private static extern bool IsWindow(nint window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "PostMessageW")]
    private static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
}
