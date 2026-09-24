using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Presence;

namespace StarBridge.HostRuntime.Settings;

internal sealed record PresenceVisibilitySnapshot(string Revision, PlayerPresenceVisibilityMode Mode);

// Existing WPF device preference. No account migration or second settings file.
// Host supplies its verified settings root and remains the only writer.
internal sealed class PresenceVisibilityStore
{
    private readonly string _root, _path;
    private readonly object _gate = new();
    public PresenceVisibilityStore(string root)
    {
        if (!Path.IsPathFullyQualified(root)) throw new ArgumentException(nameof(root));
        _root = Path.GetFullPath(root);
        _path = Path.Combine(_root, "sync-privacy.settings.json");
    }
    public PresenceVisibilitySnapshot Read()
    {
        lock (_gate) { var (revision, document) = ReadDocument(); return new(revision, Mode(document)); }
    }
    public PresenceVisibilitySnapshot Save(PlayerPresenceVisibilityMode mode, string revision, Action ensureCurrent)
    {
        if (!Valid(mode)) throw new ArgumentException(nameof(mode));
        lock (_gate)
        {
            ensureCurrent();
            var (actual, document) = ReadDocument();
            _ = Mode(document); // Never repair/overwrite malformed existing state silently.
            if (actual != revision) throw new PresenceVisibilityConflictException();
            document["PresenceVisibilityMode"] = (int)mode;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(document);
            if (bytes.Length > 65536) throw new InvalidDataException();
            CheckPaths(); ensureCurrent(); Directory.CreateDirectory(_root);
            var temporary = Path.Combine(_root, ".presence-" + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
                { file.Write(bytes); file.Flush(true); }
                CheckPaths();
                if (ReadDocument().Revision != revision) throw new PresenceVisibilityConflictException();
                ensureCurrent();
                File.Move(temporary, _path, overwrite: true);
                return new(Hash(bytes), mode);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
    }
    private (string Revision, JsonObject Document) ReadDocument()
    {
        CheckPaths(); byte[] bytes;
        try
        {
            using var file = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length is <= 0 or > 65536) throw new InvalidDataException();
            bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
        }
        catch (FileNotFoundException) { return ("missing", new()); }
        catch (DirectoryNotFoundException) { return ("missing", new()); }
        using var json = JsonDocument.Parse(bytes);
        RejectDuplicates(json.RootElement);
        return (Hash(bytes), JsonNode.Parse(bytes) as JsonObject ?? throw new InvalidDataException());
    }
    private static void RejectDuplicates(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var p in element.EnumerateObject())
            { if (!names.Add(p.Name)) throw new InvalidDataException(); RejectDuplicates(p.Value); }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var item in element.EnumerateArray()) RejectDuplicates(item);
    }
    private static PlayerPresenceVisibilityMode Mode(JsonObject d)
    {
        if (!d.ContainsKey("PresenceVisibilityMode")) return PlayerPresenceVisibilityMode.Online;
        if (d["PresenceVisibilityMode"] is not JsonValue n || !n.TryGetValue<int>(out var v) || !Valid((PlayerPresenceVisibilityMode)v))
            throw new InvalidDataException();
        return (PlayerPresenceVisibilityMode)v;
    }
    internal static bool Valid(PlayerPresenceVisibilityMode m) => m is PlayerPresenceVisibilityMode.Online or
        PlayerPresenceVisibilityMode.InGame or PlayerPresenceVisibilityMode.Invisible;
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private void CheckPaths()
    {
        for (var d = new DirectoryInfo(_root); d is not null; d = d.Parent) Check(d.FullName, true);
        Check(_path, false);
    }
    private static void Check(string path, bool directory)
    {
        try
        {
            var a = File.GetAttributes(path);
            if ((a & FileAttributes.ReparsePoint) != 0 || a.HasFlag(FileAttributes.Directory) != directory) throw new IOException();
        }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
    }
}
internal sealed class PresenceVisibilityConflictException : IOException;
