using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace StarBridge.HostRuntime.Presence;

// Shared read-only Windows mechanics. Scope and budgets remain the caller's job.
internal static class CheckedGameLogAccess
{
    internal sealed class PinnedDirectories : IDisposable
    {
        private readonly List<SafeFileHandle> _handles = [];
        internal static PinnedDirectories Open(string path, Action check)
        {
            var guard = new PinnedDirectories();
            try
            {
                var parents = new Stack<string>();
                for (string? current = path; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
                    parents.Push(current);
                while (parents.TryPop(out var parent))
                {
                    check();
                    guard._handles.Add(OpenChecked(parent, directory: true, readContent: false));
                }
                return guard;
            }
            catch { guard.Dispose(); throw; }
        }
        public void Dispose()
        {
            for (var i = _handles.Count - 1; i >= 0; i--) _handles[i].Dispose();
        }
    }

    internal static SafeFileHandle OpenChecked(string path, bool directory, bool readContent)
    {
        // OPEN_EXISTING + OPEN_REPARSE_POINT; no DELETE sharing pins checked nodes.
        var handle = CreateFile(path, readContent ? 0x80000000u : 0u,
            directory ? FileShare.Read : FileShare.ReadWrite,
            IntPtr.Zero, 3, 0x00200000u | (directory ? 0x02000000u : 0x08000000u), IntPtr.Zero);
        try
        {
            if (handle.IsInvalid || !GetFileInformationByHandle(handle, out var info)) throw new IOException();
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0 ||
                ((info.Attributes & FileAttributes.Directory) != 0) != directory)
                throw new GameplayTimeException("gameplay.history_path");
            return handle;
        }
        catch { handle.Dispose(); throw; }
    }

    // Discovery additionally rejects hard links and verifies the opened path.
    // The stamp is internal, transient and never returned through the bridge.
    internal static FileStamp Describe(SafeFileHandle handle, string expectedPath)
    {
        if (!GetFileInformationByHandle(handle, out var info)) throw new IOException();
        var buffer = new StringBuilder(2048);
        var length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
        if (length == 0 || length >= buffer.Capacity ||
            !buffer.ToString().Equals(@"\\?\" + expectedPath, StringComparison.OrdinalIgnoreCase) ||
            info.Links != 1 || (info.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
            throw new IOException();
        return new(info.Volume, info.IndexHigh, info.IndexLow,
            ((long)info.SizeHigh << 32) | info.SizeLow,
            ((long)(uint)info.Write.dwHighDateTime << 32) | (uint)info.Write.dwLowDateTime,
            ((long)(uint)info.Creation.dwHighDateTime << 32) | (uint)info.Creation.dwLowDateTime);
    }

    internal static string PersistentIdentity(SafeFileHandle handle)
    {
        // Use FILE_ID_INFO's 128-bit ID rather than assuming the legacy 64-bit
        // index is unique across restarts on every local filesystem (e.g. ReFS).
        if (!GetFileInformationByHandleEx(handle, 18, out var identity, 24) ||
            (identity.IdLow == 0 && identity.IdHigh == 0)) throw new IOException();
        return identity.Volume.ToString("X16") + identity.IdLow.ToString("X16") + identity.IdHigh.ToString("X16");
    }

    internal sealed record FileStamp(uint Volume, uint IndexHigh, uint IndexLow, long Length, long Write, long Created);

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, FileShare share,
        IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation information);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int informationClass,
        out FileIdentity information, uint size);
    [DllImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint length, uint flags);
    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        internal FileAttributes Attributes;
        internal System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        internal uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct FileIdentity
    {
        internal ulong Volume, IdLow, IdHigh;
    }
}
