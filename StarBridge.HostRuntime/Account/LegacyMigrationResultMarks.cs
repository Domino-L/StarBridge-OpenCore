using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

/// <summary>
/// "The migration result was shown for this SCM identity and this old account"
/// (account plan item 9). Only hashes are stored, never an account ID. Marks for an
/// SCM identity are dropped when the relay reports no migration again (an operator
/// rolled it back), so a later migration shows its result once more.
/// </summary>
internal sealed class LegacyMigrationResultMarks
{
    internal const string FileName = "legacy-migration-results.json";
    private const int MaximumEntries = 32;
    private const int MaximumBytes = 16 * 1024;
    private sealed record Entry(string Scm, string Legacy);
    private sealed record SavedFile(int SchemaVersion, Entry[] Shown);

    private readonly string _path;
    private readonly object _gate = new();

    internal LegacyMigrationResultMarks(string root) =>
        _path = Path.Combine(Path.GetFullPath(root), FileName);

    internal bool Shown(StarBridge.NativeBridge.BridgeAccountContext scm, string legacyAccountId)
    {
        var entry = Of(scm, legacyAccountId);
        lock (_gate) return Read().Contains(entry);
    }

    internal void MarkShown(StarBridge.NativeBridge.BridgeAccountContext scm, string legacyAccountId)
    {
        var entry = Of(scm, legacyAccountId);
        lock (_gate)
        {
            var entries = Read();
            if (entries.Contains(entry)) return;
            entries.Add(entry);
            Write(entries.Count > MaximumEntries ? entries[^MaximumEntries..] : entries);
        }
    }

    internal void Forget(StarBridge.NativeBridge.BridgeAccountContext scm)
    {
        var key = Hash(Scm(scm));
        lock (_gate)
        {
            var entries = Read();
            if (entries.RemoveAll(entry => entry.Scm == key) > 0) Write(entries);
        }
    }

    // The relay compares old account IDs ignoring case (MIGRATION-INTERFACE-073 §3).
    private static Entry Of(StarBridge.NativeBridge.BridgeAccountContext scm, string legacyAccountId) =>
        new(Hash(Scm(scm)), Hash(legacyAccountId.Trim().ToLowerInvariant()));

    private static string Scm(StarBridge.NativeBridge.BridgeAccountContext scm) =>
        scm.Environment + "\n" + scm.Authority + "\n" + scm.Subject;

    private static string Hash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("legacy-migration-result:" + value))).ToLowerInvariant();

    private List<Entry> Read()
    {
        try
        {
            var info = new FileInfo(_path);
            if (!info.Exists) return [];
            if (info.Length > MaximumBytes || info.Attributes.HasFlag(FileAttributes.ReparsePoint)) return [];
            var saved = JsonSerializer.Deserialize<SavedFile>(File.ReadAllBytes(_path), JsonOptions);
            return saved is { SchemaVersion: 1, Shown: { } shown } &&
                shown.All(entry => Valid(entry.Scm) && Valid(entry.Legacy))
                ? [.. shown.Take(MaximumEntries)] : [];
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            // Unreadable marks only mean the result may be shown once more.
            return [];
        }
    }

    private void Write(List<Entry> entries)
    {
        var temporary = _path + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            File.WriteAllBytes(temporary, JsonSerializer.SerializeToUtf8Bytes(new SavedFile(1, [.. entries]), JsonOptions));
            File.Move(temporary, _path, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Support.IdentityGateJournal.Event("migration-result", $"code=mark-failed exception={Support.IdentityGateJournal.Type(error)}");
        }
    }

    private static bool Valid(string? value) => value is { Length: 64 } && value.All(Uri.IsHexDigit);

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { MaxDepth = 4 };
}
