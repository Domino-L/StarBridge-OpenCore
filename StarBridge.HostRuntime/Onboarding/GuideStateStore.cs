using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record GuideChecklist(
    [property: JsonRequired] bool Collapsed, [property: JsonRequired] bool Dismissed,
    [property: JsonRequired] bool Celebrated, [property: JsonRequired] string[] Done);
internal sealed record GuideState(
    [property: JsonRequired] int SchemaVersion, [property: JsonRequired] bool Eligible,
    [property: JsonRequired] string[] Seen, [property: JsonRequired] GuideChecklist Checklist)
{
    internal static GuideState Empty => new(1, false, [], new(false, false, false, []));
}

internal sealed class GuideStateStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "guide-state-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false, MaxDepth = 8 };
    internal string StatePath(string profile) => Path.Combine(_directory,
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(profile))).ToLowerInvariant() + ".json");
    internal static bool ValidId(string? id) => id is not null && Regex.IsMatch(id, "\\A[a-z][a-z0-9.-]{0,47}\\z", RegexOptions.CultureInvariant);
    internal static void Invalid() => throw new LocalFirstUseException("guide.invalid_request");

    internal GuideState Read(string profile)
    {
        try
        {
            var path = StatePath(profile); Safe(path);
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (file.Length is <= 0 or > 8192) return GuideState.Empty;
            var bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
            if (file.ReadByte() != -1) return GuideState.Empty;
            using var parsed = JsonDocument.Parse(bytes); Unique(parsed.RootElement);
            var value = JsonSerializer.Deserialize<GuideState>(bytes, Json);
            if (value is null || value.SchemaVersion != 1 || !Ids(value.Seen, 64) ||
                value.Checklist is null || !Ids(value.Checklist.Done, 16)) return GuideState.Empty;
            return value;
        }
        catch (Exception e) when (e is JsonException or IOException or NotSupportedException)
        { return GuideState.Empty; }
    }

    internal GuideState Update(string profile, JsonElement[] ops, Func<bool> current)
    {
        // Validate even when this is the first write; invalid requests create no directory or lock file.
        _ = Apply(Read(profile), ops);
        var path = StatePath(profile); Safe(path); Safe(path + ".lock");
        if (!current()) throw new LocalFirstUseException("guide.context_changed");
        Directory.CreateDirectory(_directory);
        using var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        var next = Apply(Read(profile), ops);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(next, Json);
        if (bytes.Length > 8192) Invalid();
        var temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(bytes); file.Flush(true); }
            Safe(path);
            if (!current()) throw new LocalFirstUseException("guide.context_changed");
            if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
            return next;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    internal static GuideState Apply(GuideState value, JsonElement[] ops)
    {
        foreach (var op in ops)
        {
            var name = op.GetProperty("op").GetString();
            switch (name)
            {
                case "markSeen": value = value with { Seen = Add(value.Seen, op, 64) }; break;
                case "resetSeen": value = value with { Seen = [] }; break;
                case "markEligible": value = value with { Eligible = true }; break;
                case "markDone": value = value with { Checklist = value.Checklist with { Done = Add(value.Checklist.Done, op, 16) } }; break;
                case "resetChecklist": value = value with { Checklist = new(false, false, false, value.Checklist.Done) }; break;
                case "setChecklist":
                    var c = value.Checklist;
                    value = value with { Checklist = c with {
                        Collapsed = op.TryGetProperty("collapsed", out var a) ? a.GetBoolean() : c.Collapsed,
                        Dismissed = op.TryGetProperty("dismissed", out var b) ? b.GetBoolean() : c.Dismissed,
                        Celebrated = op.TryGetProperty("celebrated", out var d) ? d.GetBoolean() : c.Celebrated } };
                    break;
                default: Invalid(); break;
            }
        }
        return value;
    }
    private static string[] Add(string[] values, JsonElement op, int max)
    {
        var id = op.GetProperty("id").GetString()!;
        if (values.Contains(id, StringComparer.Ordinal)) return values;
        if (values.Length >= max) Invalid();
        return [.. values, id];
    }
    private static bool Ids(string[]? ids, int max) => ids is not null && ids.Length <= max &&
        ids.All(ValidId) && ids.Distinct(StringComparer.Ordinal).Count() == ids.Length;
    private static void Unique(JsonElement node)
    {
        if (node.ValueKind != JsonValueKind.Object) return;
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var p in node.EnumerateObject()) { if (!names.Add(p.Name)) throw new JsonException(); Unique(p.Value); }
    }
    private static void Safe(string path)
    {
        for (string? node = Path.GetFullPath(path); node is not null; node = Path.GetDirectoryName(node))
        {
            try { if (File.GetAttributes(node).HasFlag(FileAttributes.ReparsePoint)) throw new IOException(); }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
}
