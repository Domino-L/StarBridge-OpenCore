namespace StarBridge.HostRuntime.Settings;

using System.Text.Json;

// Process-local menu recovery only; never stores account IDs or tool contents.
// An explicit client exit closes the session. Pipe loss/Host.Dispose does not.
internal sealed class MenuSessionRecoveryStore(string dataRoot)
{
    private readonly string _path = Path.Combine(Path.GetFullPath(dataRoot), "menu-session.v1.json");
    private readonly object _gate = new();
    internal sealed record Session(string Token, bool PreviousInterrupted);
    private Session? _session;

    internal Session Begin()
    {
        lock (_gate)
        {
            using var ownership = Lock();
            var prior = Read();
            _session ??= new(Guid.NewGuid().ToString("N"), prior is { Clean: false });
            // Reopening after an exit attempt re-arms the interruption marker.
            if (_begun && prior?.Token != _session.Token)
                throw new ApplicationPreferencesException("menuRecovery.owner_changed", "Menu session changed", false);
            Write(_session.Token, false);
            _begun = true;
            return _session;
        }
    }
    private bool _begun;

    internal void Finish(string token)
    {
        lock (_gate)
        {
            using var ownership = Lock();
            var current = Read();
            if (_session is null || token != _session.Token || current?.Token != token)
                throw new ApplicationPreferencesException("menuRecovery.owner_changed", "Menu session changed", false);
            Write(token, true);
        }
    }

    private FileStream Lock()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        return new FileStream(_path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    private sealed record Marker(string Token, bool Clean);
    private Marker? Read()
    {
        if (!File.Exists(_path)) return null;
        // Corruption is not evidence of a normal exit.
        if (new FileInfo(_path).Length > 512) return new("", false);
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(_path));
            var value = document.RootElement;
            if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Count() != 3 ||
                !value.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1 ||
                !value.TryGetProperty("token", out var token) || token.ValueKind != JsonValueKind.String || !ValidToken(token.GetString()) ||
                !value.TryGetProperty("clean", out var clean) || clean.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                return new("", false);
            return new(token.GetString()!, clean.GetBoolean());
        }
        catch (JsonException) { return new("", false); }
    }
    internal static bool ValidToken(string? token) => token is { Length: 32 } && token.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private void Write(string token, bool clean)
    {
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(file, new { schemaVersion = 1, token, clean });
                file.Flush(true);
            }
            File.Move(temporary, _path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
