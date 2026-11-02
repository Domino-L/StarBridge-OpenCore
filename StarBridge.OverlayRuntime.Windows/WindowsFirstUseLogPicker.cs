using System.Diagnostics;
using System.Runtime.InteropServices;
using StarBridge.HostRuntime.Onboarding;
using Forms = System.Windows.Forms;

namespace StarBridge.OverlayRuntime.Windows;

public sealed class WindowsFirstUseLogPicker(int parentProcessId) : IFirstUseLogPicker
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
                using var dialog = new Forms.OpenFileDialog { Filter = "Game.log|Game.log", CheckFileExists = true,
                    Multiselect = false, RestoreDirectory = true, Title = locale.StartsWith("en", StringComparison.OrdinalIgnoreCase)
                        ? "Select Game.log" : locale == "zh-TW" ? "選擇 Game.log" : "选择 Game.log" };
                var threadId = GetCurrentThreadId();
                void Close() => EnumThreadWindows(threadId, (window, _) => { PostMessage(window, 0x0010, 0, 0); return true; }, 0);
                using var cancellation = token.Register(Close);
                using var timer = new Forms.Timer { Interval = 100 };
                timer.Tick += (_, _) => { if (token.IsCancellationRequested) Close(); };
                timer.Start();
                var selected = dialog.ShowDialog(new Owner(owner)) == Forms.DialogResult.OK;
                token.ThrowIfCancellationRequested();
                completion.TrySetResult(selected ? dialog.FileName : null);
            }
            catch (OperationCanceledException) { completion.TrySetCanceled(token); }
            catch { completion.TrySetException(new InvalidOperationException("Log selection unavailable.")); }
        }) { IsBackground = true, Name = "StarBridge first-use log selection" };
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
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
