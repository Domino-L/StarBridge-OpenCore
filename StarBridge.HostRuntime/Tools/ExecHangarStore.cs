using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Tools;

namespace StarBridge.HostRuntime.Tools;

internal sealed record ExecHangarDocument(int SchemaVersion = 1, int Revision = 0,
    ExecHangarReminders? Reminders = null, ExecHangarConfig? Config = null, DateTimeOffset? FetchedAt = null,
    string[]? Receipts = null, ExecHangarMonitoring? Monitoring = null, ExecHangarNotice? PendingStart = null,
    DateTimeOffset? LegacyMutedBoundary = null, ExecHangarGameMonitoring? GameMonitoring = null);

/// <summary>One device-local atomic document; corrupt or redirected files are never replaced.</summary>
internal sealed class ExecHangarStore(string dataRoot)
{
    private readonly string _root = Path.GetFullPath(dataRoot);
    private string PathName => Path.Combine(_root, "exec-hangar.v1.json");
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web) {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 8
    };
    private void Guard()
    {
        for (var directory = new DirectoryInfo(_root); directory != null; directory = directory.Parent)
            if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Redirected reminder directory.");
        if (Path.Exists(PathName) && File.GetAttributes(PathName).HasFlag(FileAttributes.ReparsePoint))
            throw new IOException("Redirected reminder file.");
    }
    public ExecHangarDocument Read()
    {
        Guard(); if (!File.Exists(PathName)) return new(Reminders: new(), Receipts: []);
        if (new FileInfo(PathName).Length > 65536) throw new InvalidDataException();
        using var json = JsonDocument.Parse(File.ReadAllBytes(PathName), new() { MaxDepth = 8 });
        void Unique(JsonElement value) {
            if (value.ValueKind == JsonValueKind.Object) {
                var fields = value.EnumerateObject().ToArray();
                if (fields.Select(p => p.Name).Distinct().Count() != fields.Length) throw new InvalidDataException();
                foreach (var field in fields) Unique(field.Value);
            }
        }
        Unique(json.RootElement);
        var value = json.RootElement.Deserialize<ExecHangarDocument>(Options) ?? throw new InvalidDataException();
        if (value.SchemaVersion != 1 || value.Revision < 0 || value.Reminders == null || value.Receipts == null ||
            value.Receipts.Length > 256 || value.Receipts.Any(key => key == null || key.Length > 100) ||
            (value.Config == null) != (value.FetchedAt == null)) throw new InvalidDataException();
        value.Reminders.Validate(); value.Config?.Validate(); value.Monitoring?.Validate(); value.GameMonitoring?.Validate();
        if (value.PendingStart is {} pending && (!value.Reminders.Enabled || pending.Boundary < pending.Due ||
            pending.Boundary - pending.Due > TimeSpan.FromMinutes(120) || value.Monitoring is {} watch &&
            (pending.Due < watch.StartedAt || pending.Due > watch.EndsAt || pending.Boundary > watch.EndsAt) ||
            pending.Kind is not ("beforeOpen" or "beforeClose" or "beforeChange" or "leave"))) throw new InvalidDataException();
        return value;
    }
    public void Write(ExecHangarDocument value)
    {
        Guard(); Directory.CreateDirectory(_root); var temp = PathName + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try {
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) {
                JsonSerializer.Serialize(file, value, Options); file.Flush(true);
            }
            Guard(); File.Move(temp, PathName, true);
        } finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
