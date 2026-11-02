using System.Buffers.Binary;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

/// <summary>NTFS junction between two owned synthetic fixtures, without changing
/// Windows privileges or requiring symbolic-link creation rights.</summary>
internal static class CacheFixtureJunction
{
    internal static void Create(string fixtureRoot, string link, string target)
    {
        ValidateRoot(fixtureRoot); ValidateRoot(target);
        link = ValidateChild(fixtureRoot, link);
        var substitute = @"\??\" + Path.GetFullPath(target);
        var print = Path.GetFullPath(target);
        var paths = Encoding.Unicode.GetBytes(substitute + "\0" + print + "\0");
        var buffer = new byte[16 + paths.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(buffer, 0xA0000003);
        BinaryPrimitives.WriteUInt16LittleEndian(buffer.AsSpan(4), checked((ushort)(8 + paths.Length)));
        BinaryPrimitives.WriteUInt16LittleEndian(buffer.AsSpan(10), checked((ushort)(substitute.Length * 2)));
        BinaryPrimitives.WriteUInt16LittleEndian(buffer.AsSpan(12), checked((ushort)((substitute.Length + 1) * 2)));
        BinaryPrimitives.WriteUInt16LittleEndian(buffer.AsSpan(14), checked((ushort)(print.Length * 2)));
        paths.CopyTo(buffer, 16);
        Directory.CreateDirectory(link);
        try
        {
            using var handle = CreateFile(link, 0x40000000, FileShare.Read | FileShare.Write | FileShare.Delete,
                IntPtr.Zero, FileMode.Open, 0x02000000 | 0x00200000, IntPtr.Zero);
            if (handle.IsInvalid || !DeviceIoControl(handle, 0x000900A4, buffer, buffer.Length,
                    IntPtr.Zero, 0, out _, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastPInvokeError());
        }
        catch
        {
            Directory.Delete(link); // Owned empty directory or link; never recursive.
            throw;
        }
    }

    internal static void Remove(string fixtureRoot, string link)
    {
        link = ValidateChild(fixtureRoot, link);
        if ((File.GetAttributes(link) & FileAttributes.ReparsePoint) == 0)
            throw new InvalidOperationException("Expected the owned fixture junction");
        Directory.Delete(link); // Remove the junction itself, not its target.
    }

    private static void ValidateRoot(string root)
    {
        var full = Path.GetFullPath(root);
        var parent = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
        var name = Path.GetFileName(full);
        var validName = new[] { "StarBridge-image-cache-safety-", "StarBridge-organization-image-maintenance-" }
            .Any(prefix => name.StartsWith(prefix, StringComparison.Ordinal) && Guid.TryParseExact(name[prefix.Length..], "N", out _));
        if (!string.Equals(Path.GetDirectoryName(full), parent, StringComparison.OrdinalIgnoreCase) ||
            !validName)
            throw new InvalidOperationException("Junction is limited to owned synthetic roots");
    }

    private static string ValidateChild(string root, string path)
    {
        ValidateRoot(root);
        var full = Path.GetFullPath(path);
        if (!full.StartsWith(Path.GetFullPath(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Junction escaped its fixture");
        return full;
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, FileShare share,
        IntPtr security, FileMode mode, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeviceIoControl(SafeFileHandle handle, uint code, byte[] input,
        int inputLength, IntPtr output, int outputLength, out int returned, IntPtr overlapped);
}
