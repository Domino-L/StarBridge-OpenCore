using System.Runtime.InteropServices;
using System.Text;
using StarBridge.HostRuntime.Support;

namespace StarBridge.NativeHost;

/// <summary>Native save picker, owned by the Flutter window; no WPF dependency.</summary>
internal sealed class WindowsGameplayExportPicker(Func<nint> ownerWindow) : IGameplayExportPicker, ILocalEventExportPicker
{
    public Task<string?> ChooseNewJsonFileAsync(string suggestedName, string locale, CancellationToken cancellation) =>
        ChooseAsync(suggestedName, locale, false, cancellation);

    public Task<string?> ChooseNewTextFileAsync(string suggestedName, string locale, CancellationToken cancellation) =>
        ChooseAsync(suggestedName, locale, true, cancellation);

    private Task<string?> ChooseAsync(string suggestedName, string locale, bool text, CancellationToken cancellation)
    {
        var completion = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try { completion.TrySetResult(Choose(suggestedName, locale, text, cancellation)); }
            catch (OperationCanceledException) { completion.TrySetCanceled(cancellation); }
            catch (Exception error) { completion.TrySetException(error); }
        }) { IsBackground = true, Name = "StarBridge export picker" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return completion.Task;
    }

    private string? Choose(string suggestedName, string locale, bool text, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        var owner = ownerWindow();
        if (owner == 0 || !IsWindow(owner)) throw new InvalidOperationException();
        nint dialog = 0;
        Hook hook = (window, message, _, _) =>
        {
            if (message == 0x0110) // WM_INITDIALOG on the Explorer-style child hook.
            {
                Interlocked.Exchange(ref dialog, GetParent(window));
                if (cancellation.IsCancellationRequested) PostMessage(dialog, 0x0010, 0, 0);
            }
            return 0;
        };
        using var registration = cancellation.Register(() =>
        {
            var window = Interlocked.CompareExchange(ref dialog, 0, 0);
            if (window != 0) PostMessage(window, 0x0010, 0, 0); // WM_CLOSE
        });
        var file = new StringBuilder(suggestedName, 32768);
        var options = new OpenFileName
        {
            StructSize = Marshal.SizeOf<OpenFileName>(), Owner = owner,
            Filter = text ? "TXT (*.txt)\0*.txt\0\0" : "JSON (*.json)\0*.json\0\0", FilterIndex = 1,
            File = file, MaxFile = file.Capacity, DefaultExtension = text ? "txt" : "json",
            Title = text ? locale switch
            {
                "en" => "Export local event history",
                "zh-TW" => "匯出本機事件記錄",
                _ => "导出本地事件日志"
            } : locale switch
            {
                "en" => "Export gameplay data to a new JSON file",
                "zh-TW" => "匯出遊玩資料（新 JSON 檔案）",
                _ => "导出游玩数据（新 JSON 文件）"
            },
            Flags = 0x00080000 | 0x00000020 | 0x00000800 | 0x00000008 | 0x00000004,
            Hook = hook
        };
        var chosen = GetSaveFileName(ref options);
        var error = chosen ? 0 : CommDlgExtendedError();
        Interlocked.Exchange(ref dialog, 0);
        GC.KeepAlive(hook);
        cancellation.ThrowIfCancellationRequested();
        if (!chosen && error != 0) throw new InvalidOperationException();
        return chosen ? file.ToString() : null;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nuint Hook(nint window, uint message, nuint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct OpenFileName
    {
        public int StructSize;
        public nint Owner;
        public nint Instance;
        public string? Filter;
        public nint CustomFilter;
        public int MaxCustomFilter;
        public int FilterIndex;
        public StringBuilder File;
        public int MaxFile;
        public nint FileTitle;
        public int MaxFileTitle;
        public string? InitialDirectory;
        public string? Title;
        public int Flags;
        public ushort FileOffset;
        public ushort FileExtension;
        public string? DefaultExtension;
        public nint CustomData;
        public Hook Hook;
        public string? TemplateName;
        public nint Reserved;
        public int ReservedSize;
        public int FlagsEx;
    }

    [DllImport("comdlg32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetSaveFileNameW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSaveFileName(ref OpenFileName options);
    [DllImport("comdlg32.dll")]
    private static extern int CommDlgExtendedError();
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(nint window);
    [DllImport("user32.dll")]
    private static extern nint GetParent(nint window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "PostMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(nint window, uint message, nuint wParam, nint lParam);
}
