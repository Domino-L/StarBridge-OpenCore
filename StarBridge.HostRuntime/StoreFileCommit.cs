using System.Diagnostics;
using System.IO;
using System.Security.AccessControl;

namespace StarBridge.HostRuntime;

// Replaces a store file that lease-free readers may open at any moment.
// File.Replace exposes a gap: a reader then sees a missing file (read as "no data")
// or a sharing violation. An overwriting move has no such window, but is refused
// while a reader has the old file open, which lasts only for that read. Unlike
// File.Replace it keeps the new file's DACL, so carry the old one across first
// and refuse the commit if that fails.
internal static class StoreFileCommit
{
    private static readonly TimeSpan CommitBudget = TimeSpan.FromSeconds(2);

    // False when unchanged() withdrew the commit during a wait; nothing was replaced.
    internal static bool Replace(string temporary, string path, Func<bool> unchanged, string timeoutMessage)
    {
        var waited = Stopwatch.StartNew();
        for (var delay = 1; ; delay = Math.Min(delay * 2, 50))
        {
            CarryDacl(temporary, path);
            try { File.Move(temporary, path, overwrite: true); return true; }
            catch (Exception error) when (error is UnauthorizedAccessException || error is IOException && IsSharingConflict(error))
            {
                // Still the IOException that callers handle; the inner error keeps the cause.
                if (waited.Elapsed >= CommitBudget) throw new IOException(timeoutMessage, error);
            }
            Thread.Sleep(delay);
            if (!unchanged()) return false;
        }
    }

    // For a store whose lease does not bind every outside writer: a wait may outlast
    // what the caller read, so every further attempt also compares the file itself.
    internal static bool ReplaceIfUnchanged(string temporary, string path, Func<bool> allowed, int maximumBytes, string timeoutMessage)
    {
        var before = ReadBounded(path, maximumBytes) ?? throw new IOException(timeoutMessage);
        return Replace(temporary, path, () => allowed() && SameContent(path, before), timeoutMessage);
    }

    private static bool SameContent(string path, byte[] expected)
    {
        try { return ReadBounded(path, expected.Length)?.AsSpan().SequenceEqual(expected) == true; }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }

    // Null when the file outgrew the bound: never allocate what the store would refuse to read.
    private static byte[]? ReadBounded(string path, int maximumBytes)
    {
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (file.Length > maximumBytes) return null;
        var bytes = new byte[(int)file.Length];
        file.ReadExactly(bytes);
        return bytes;
    }

    internal static bool IsSharingConflict(Exception error) => (error.HResult & 0xFFFF) is 32 or 33;

    private static void CarryDacl(string temporary, string path)
    {
        var existing = new FileInfo(path);
        if (!existing.Exists) return;
        // A read FileSecurity persists nothing: only sections marked modified are written.
        var dacl = new FileSecurity();
        dacl.SetSecurityDescriptorSddlForm(existing.GetAccessControl(AccessControlSections.Access)
            .GetSecurityDescriptorSddlForm(AccessControlSections.Access), AccessControlSections.Access);
        new FileInfo(temporary).SetAccessControl(dacl);
    }
}
