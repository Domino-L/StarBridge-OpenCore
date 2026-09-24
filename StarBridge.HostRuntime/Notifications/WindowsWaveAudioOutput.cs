namespace StarBridge.HostRuntime.Notifications;

using System.Runtime.InteropServices;

internal interface INotificationAudioOutput : IDisposable
{
    bool TryPlay(byte[] wave);
    void Stop();
}

// One retained buffer and one output for the entire Host. Stop before unpinning.
internal sealed class WindowsWaveAudioOutput : INotificationAudioOutput
{
    private GCHandle _buffer;
    public bool TryPlay(byte[] wave)
    {
        Stop();
        if (!OperatingSystem.IsWindows()) return false;
        _buffer = GCHandle.Alloc(wave, GCHandleType.Pinned);
        try {
            if (PlaySound(_buffer.AddrOfPinnedObject(), IntPtr.Zero, 0x0001 | 0x0002 | 0x0004)) return true;
        } catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException) { }
        Stop(); return false;
    }
    public void Stop()
    {
        try {
            if (OperatingSystem.IsWindows()) PlaySound(IntPtr.Zero, IntPtr.Zero, 0);
        } catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException) { }
        finally { if (_buffer.IsAllocated) _buffer.Free(); }
    }
    public void Dispose() => Stop();
    [DllImport("winmm.dll", EntryPoint = "PlaySoundW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PlaySound(IntPtr sound, IntPtr module, uint flags);
}
