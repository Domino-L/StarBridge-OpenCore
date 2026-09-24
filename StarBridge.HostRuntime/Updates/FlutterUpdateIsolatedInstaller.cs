using System.Diagnostics;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Complete installation adapter restricted to newly-created TEMP fixtures.
/// Uses the real download, ticket, helper and transaction; never a production fallback.</summary>
internal sealed class FlutterUpdateIsolatedInstaller : IDisposable
{
    private readonly FlutterUpdateRuntime _runtime;
    private readonly string _helper, _parent;
    private readonly FlutterUpdateTarget _target;
    private readonly Process _client, _host;
    private readonly Dictionary<string, string> _trust;
    private string? _root;
    internal FlutterUpdateInstallation Installation { get; }
    internal Process? HelperProcess { get; private set; }
    internal string? TransactionRoot => _root;

    internal FlutterUpdateIsolatedInstaller(FlutterUpdateRuntime runtime, string helper, string parent,
        FlutterUpdateTarget target, Process client, Process host, IReadOnlyDictionary<string, string> isolatedTrust)
    {
        _runtime = runtime; _helper = Path.GetFullPath(helper); _parent = Path.GetFullPath(parent);
        _target = target; _client = client; _host = host; _trust = new(isolatedTrust);
        RequireFixture();
        Installation = new FlutterUpdateInstallation(PrepareAsync, HandoffAsync);
    }

    private void RequireFixture()
    {
        var temp = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
        if (!string.Equals(Path.GetDirectoryName(_parent), temp, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFileName(_parent).StartsWith("starbridge-update-integration-", StringComparison.Ordinal) ||
            !Directory.Exists(_parent) || _helper.StartsWith(_parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Not an isolated update fixture.");
        for (var directory = new DirectoryInfo(_parent); directory is not null; directory = directory.Parent)
            if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Redirected fixture.");
        var clientRoot = Path.Combine(_parent, "client");
        if (_client.HasExited || _host.HasExited ||
            !string.Equals(_client.MainModule?.FileName, Path.Combine(clientRoot, "starbridge_flutter.exe"), StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(_host.MainModule?.FileName, Path.Combine(clientRoot, "native_host", "StarBridge.NativeHost.exe"), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Fixture owners do not match.");
    }

    private async Task<string> PrepareAsync(string version, CancellationToken cancellation)
    {
        RequireFixture();
        if (HelperProcess is { HasExited: false }) throw new InvalidOperationException("Helper already active.");
        _root = Path.Combine(_parent, ".starbridge-update-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        return await _runtime.StageAsync(_root, cancellation, version);
    }

    private async Task HandoffAsync(string stage, CancellationToken cancellation)
    {
        RequireFixture();
        cancellation.ThrowIfCancellationRequested();
        var artifact = _runtime.RequirePreparedArtifact(stage);
        var root = _root ?? throw new InvalidOperationException("No prepared transaction.");
        if (Path.GetDirectoryName(stage) != root || Path.GetDirectoryName(artifact.Archive) != root)
            throw new InvalidDataException("Candidate is outside the owned transaction.");
        // Preserve the signed archive for independent helper revalidation. No UI
        // manifest, trust root or executable path participates in the plan.
        File.Copy(artifact.Archive, Path.Combine(root, "package.zip"), overwrite: false);
        Write(root, "manifest.json", artifact.Manifest);
        Write(root, "isolated-public-keys.json", _trust);
        Write(root, "plan.json", new { schemaVersion = 1, installationName = "client",
            architecture = _target.Architecture, channel = _target.Channel, currentVersion = _target.CurrentVersion,
            clientPid = _client.Id, clientStartTicks = _client.StartTime.ToUniversalTime().Ticks,
            hostPid = _host.Id, hostStartTicks = _host.StartTime.ToUniversalTime().Ticks });
        HelperProcess?.Dispose();
        HelperProcess = await FlutterUpdateHandoff.StartIsolatedAsync(_helper, Path.Combine(root, "plan.json"), cancellation);
    }

    private static void Write<T>(string root, string name, T value)
    {
        using var stream = new FileStream(Path.Combine(root, name), FileMode.CreateNew, FileAccess.Write, FileShare.None);
        JsonSerializer.Serialize(stream, value, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        stream.Flush(flushToDisk: true);
    }
    public void Dispose() => HelperProcess?.Dispose();
}
