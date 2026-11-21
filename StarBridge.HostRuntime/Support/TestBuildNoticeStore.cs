using System.Text.Json;

namespace StarBridge.HostRuntime.Support;

/// <summary>Device-local acknowledgement compatible with WPF. Never reads credentials.</summary>
public sealed class TestBuildNoticeStore(string dataRoot)
{
    public const string TermsVersion = "2026-11-05-v5";
    // Each terms version keeps its own file. 0.7.2.1 reads LegacyFileName and requires
    // its own 2026-10-31-v4, so sharing one file made every switch between 0.7.2.1 and
    // 0.7.3 overwrite the other's record and ask again (11-08). LegacyFileName is never
    // read, written or deleted here. A future terms bump changes TermsVersion and
    // FileName together.
    public const string FileName = "official-binary-license.v5.accepted.json";
    public const string LegacyFileName = "official-binary-license.accepted.json";
    private readonly string _root = Path.GetFullPath(dataRoot);
    private string FilePath => Path.Combine(_root, FileName);

    public bool IsAcknowledged()
    {
        try
        {
            CheckPath();
            using var stream = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > 8192) return false;
            using var document = JsonDocument.Parse(stream);
            var value = document.RootElement;
            return value.GetProperty("SchemaVersion").GetInt32() == 1 &&
                value.GetProperty("TermsVersion").GetString() == TermsVersion;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException) { return false; }
    }

    public void Acknowledge(string termsVersion, string document, Func<bool> canCommit)
    {
        if (termsVersion != TermsVersion || string.IsNullOrWhiteSpace(document))
            throw new InvalidOperationException("Unconfirmed notice document.");
        CheckPath();
        Directory.CreateDirectory(_root);
        var temporary = Path.Combine(_root, $".notice-{Guid.NewGuid():N}.tmp");
        try
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new {
                SchemaVersion = 1, TermsVersion, AcceptedAtUtc = DateTimeOffset.UtcNow,
                AppVersion = "Flutter", TermsSha256 = Convert.ToHexString(
                    System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(document))).ToLowerInvariant()
            });
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.WriteThrough)) { file.Write(bytes); file.Flush(true); }
            CheckPath();
            if (!canCommit()) throw new OperationCanceledException();
            File.Move(temporary, FilePath, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private void CheckPath()
    {
        for (var directory = new DirectoryInfo(_root); directory is not null; directory = directory.Parent)
            if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException();
        if (File.Exists(FilePath) && (File.GetAttributes(FilePath) &
            (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0) throw new IOException();
    }
}
