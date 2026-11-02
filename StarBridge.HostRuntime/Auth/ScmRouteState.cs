using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

// Device-local route policy and failure cooldown. This file never contains account data.
internal sealed class ScmRouteState(string path, Func<DateTimeOffset>? clock = null)
{
    private readonly object _gate = new();
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private DateTimeOffset Now => (clock ?? (() => DateTimeOffset.UtcNow))();
    private string _startupMode = "auto";
    private bool _domestic;
    private string? _reason;
    internal bool IsDomestic { get { lock (_gate) return _domestic; } }

    private sealed record State(string ScmRouteMode = "auto", DateTimeOffset? DomesticLoginFailedAt = null);
    internal sealed record Projection(string Mode, string Active,
        [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.Never)]
        string? Reason, bool RestartRequired);

    // The state file and the folder that holds it must be ordinary: a junction, symlink or mount point
    // on either is never followed (read as default, write refused).
    private bool Redirected()
    {
        var directory = Path.GetDirectoryName(path);
        return File.Exists(path) && new FileInfo(path).Attributes.HasFlag(FileAttributes.ReparsePoint) ||
            directory is not null && Directory.Exists(directory) &&
            new DirectoryInfo(directory).Attributes.HasFlag(FileAttributes.ReparsePoint);
    }

    private State Read()
    {
        try
        {
            if (!File.Exists(path) || Redirected()) return new();
            var info = new FileInfo(path);
            if (info.Length > 4096) return new();
            var state = JsonSerializer.Deserialize<State>(File.ReadAllText(path), Json);
            return state is not null && state.ScmRouteMode is "auto" or "overseas" ? state : new();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        { return new(); }
    }

    private void Write(State state)
    {
        if (Redirected()) throw new IOException("Route state path is redirected.");
        if (state == new State()) { if (File.Exists(path)) File.Delete(path); return; }
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (Redirected()) throw new IOException("Route state path is redirected.");
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(state, Json));
            File.Move(temp, path, true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    internal string? StartupFallback(bool automaticRouting)
    {
        lock (_gate)
        {
            var state = Read();
            _startupMode = state.ScmRouteMode;
            if (state.DomesticLoginFailedAt is { } failed && (failed > Now || Now - failed >= TimeSpan.FromHours(24)))
            {
                state = state with { DomesticLoginFailedAt = null };
                TryWrite(state);
            }
            if (!automaticRouting) return null;
            if (state.ScmRouteMode == "overseas") return "user-overseas";
            return state.DomesticLoginFailedAt is not null ? "fallback-login" : null;
        }
    }

    internal void SetActive(ScmRegionRoute route)
    {
        lock (_gate)
        {
            _domestic = route.ApiBaseUri.Host.Equals("flowcld.xyz", StringComparison.OrdinalIgnoreCase);
            _reason = route.Source switch
            {
                "fallback-preflight" => "domesticUnavailable",
                "fallback-login" => "domesticLoginFailed",
                "user-overseas" => "userOverseas",
                _ => null
            };
        }
    }

    internal Projection Inspect()
    {
        lock (_gate)
        {
            var mode = Read().ScmRouteMode;
            return new(mode, _domestic ? "domestic" : "overseas", _reason, mode != _startupMode);
        }
    }

    internal Projection SaveMode(string mode)
    {
        if (mode is not ("auto" or "overseas")) throw new ArgumentException("Invalid route mode.");
        lock (_gate) { Write(Read() with { ScmRouteMode = mode }); return Inspect(); }
    }

    internal void LoginNetworkFailed()
    {
        lock (_gate) { if (_domestic) TryWrite(Read() with { DomesticLoginFailedAt = Now }); }
    }

    internal void LoginSucceeded()
    {
        lock (_gate) { if (!_domestic) TryWrite(Read() with { DomesticLoginFailedAt = null }); }
    }

    private void TryWrite(State state)
    {
        try { Write(state); }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        { ScmRegionDiagnostics.Write("failure=route-state-write"); }
    }
}
