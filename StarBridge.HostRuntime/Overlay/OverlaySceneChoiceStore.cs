using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

internal sealed record OverlaySceneChoice(long Revision = 0, string Mode = "auto", string? Code = null);

/// <summary>Account-local display choice; never part of a shareable preset.</summary>
internal sealed class OverlaySceneChoiceStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "overlay-source-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private sealed record FileData(int SchemaVersion, string OwnerHash, OverlaySceneChoice Choice);
    private static string Hash(BridgeAccountContext owner) => Convert.ToHexString(
        SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(owner)));
    private string PathFor(string hash) => Path.Combine(_directory, hash + ".json");
    private static void Safe(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) &&
                File.GetAttributes(current).HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Linked source settings path.");
    }
    internal OverlaySceneChoice Read(BridgeAccountContext owner)
    {
        var hash = Hash(owner); var path = PathFor(hash);
        Safe(path);
        if (!File.Exists(path)) return new();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is <= 0 or > 4096) throw new InvalidDataException();
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        using var document = JsonDocument.Parse(bytes);
        static void Unique(JsonElement node)
        {
            if (node.ValueKind != JsonValueKind.Object) return;
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in node.EnumerateObject())
            { if (!names.Add(property.Name)) throw new InvalidDataException(); Unique(property.Value); }
        }
        Unique(document.RootElement);
        var data = JsonSerializer.Deserialize<FileData>(bytes, Json);
        if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash || data.Choice is null ||
            data.Choice.Revision < 0 || !Valid(data.Choice.Mode, data.Choice.Code)) throw new InvalidDataException();
        return data.Choice;
    }
    internal static bool Valid(string mode, string? code) => mode is "auto" or "room" ? code is null :
        mode == "community" && !string.IsNullOrWhiteSpace(code) && code.Length <= 256 && !code.Any(char.IsControl);
    internal OverlaySceneChoice Save(BridgeAccountContext owner, long revision, string mode, string? code, Func<bool> current)
    {
        if (!Valid(mode, code) || revision < 0 || revision == long.MaxValue) throw new InvalidDataException();
        Safe(_directory); Directory.CreateDirectory(_directory);
        var path = PathFor(Hash(owner)); Safe(path); Safe(path + ".lock");
        using var guard = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.Write, FileShare.None);
        if (Read(owner).Revision != revision) throw new InvalidOperationException("Source revision changed.");
        var choice = new OverlaySceneChoice(revision + 1, mode, code);
        var temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(stream, new FileData(1, Hash(owner), choice), Json); stream.Flush(true); }
            if (!current()) throw new OperationCanceledException();
            File.Move(temporary, path, true);
            return choice;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
