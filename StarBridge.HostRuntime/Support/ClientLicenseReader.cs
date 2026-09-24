namespace StarBridge.HostRuntime.Support;

using System.Text;

public sealed record ClientLicenseDocument(string State, string? Text);

/// <summary>Reads the existing distribution document, never acknowledgement or entitlement state.</summary>
public sealed class ClientLicenseReader
{
    public const string FileName = "OFFICIAL-BINARY-LICENSE.txt";
    public const int MaximumBytes = 64 * 1024;
    private readonly string _directory;

    public ClientLicenseReader(string installationDirectory)
    {
        if (!Path.IsPathFullyQualified(installationDirectory) || installationDirectory.StartsWith(@"\\"))
            throw new ArgumentException("A local installation directory is required.");
        _directory = Path.GetFullPath(installationDirectory);
    }

    public async Task<ClientLicenseDocument> ReadAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            // No parent-directory discovery or user-provided document path. Refuse redirected files.
            for (var folder = new DirectoryInfo(_directory); folder is not null; folder = folder.Parent)
                if ((File.GetAttributes(folder.FullName) & FileAttributes.ReparsePoint) != 0)
                    return new("unreadable", null);
            var path = Path.Combine(_directory, FileName);
            if ((File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
                return new("unreadable", null);
            await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read,
                4096, FileOptions.Asynchronous | FileOptions.SequentialScan);
            if (stream.Length is <= 0 or > MaximumBytes) return new("unreadable", null);
            var bytes = new byte[(int)stream.Length];
            await stream.ReadExactlyAsync(bytes, cancellationToken);
            if (stream.ReadByte() != -1) return new("unreadable", null);
            var offset = bytes.AsSpan().StartsWith(new byte[] { 0xEF, 0xBB, 0xBF }) ? 3 : 0;
            var text = new UTF8Encoding(false, true).GetString(bytes, offset, bytes.Length - offset);
            if (string.IsNullOrWhiteSpace(text) ||
                text.Any(c => char.IsControl(c) && c is not ('\t' or '\r' or '\n')))
                return new("unreadable", null);
            cancellationToken.ThrowIfCancellationRequested();
            return new("ready", text);
        }
        catch (OperationCanceledException) { throw; }
        catch (FileNotFoundException) { return new("missing", null); }
        catch (DirectoryNotFoundException) { return new("missing", null); }
        catch { return new("unreadable", null); }
    }
}
