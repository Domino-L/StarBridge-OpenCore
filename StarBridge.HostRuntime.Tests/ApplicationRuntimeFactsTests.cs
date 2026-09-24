using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class ApplicationRuntimeFactsTests
{
    internal static async Task CompositeRoutesOnlyExactRuntimeRequest()
    {
        var root = TempRoot();
        try
        {
            var other = new UnusedDispatcher();
            using var runtime = new RuntimeFactsBridgeDispatcher(new(root, null), () => 4);
            using var composite = new CompositeBridgeDispatcher(other, other, other, runtimeFacts: runtime);
            Equal("ok", (await composite.DispatchAsync(Request())).Response.Status);
            Equal("error", (await composite.DispatchAsync(Request() with { Name = "diagnostics.other" })).Response.Status);
            composite.Dispose();
            Equal("error", (await runtime.DispatchAsync(Request())).Response.Status);
        }
        finally { Directory.Delete(root, true); }
    }

    private sealed class UnusedDispatcher : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Unrelated owner must not receive runtime facts.");
        public void Dispose() { }
    }

    internal static Task ReadsOnlyConfiguredExecutableAndDoesNotCreateFolders()
    {
        var root = TempRoot();
        try
        {
            var executable = Path.Combine(root, "client.exe");
            File.WriteAllText(executable, "synthetic PE reader seam");
            var missing = Path.Combine(root, "not-created");
            var reads = 0;
            var reader = new ApplicationRuntimeFactsReader(missing, executable, null,
                path => { Equal(executable, path); reads++; return "0.1.0+7"; });
            var facts = reader.Read();
            Equal("0.1.0+7", facts.ApplicationVersion);
            Equal(missing, facts.DataDirectory);
            Equal(Path.Combine(missing, "Images"), facts.ImageCacheDirectory);
            Equal(false, facts.ImageCacheExists);
            Equal(false, Directory.Exists(missing));
            Equal(1, reads);
            Equal<string?>(null, facts.ServerOrigin);
            var invalid = new ApplicationRuntimeFactsReader(missing, "relative.exe", null,
                _ => throw new InvalidOperationException("must not read"));
            Equal<string?>(null, invalid.Read().ApplicationVersion);
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }

    internal static Task VersionAndEndpointNeverLeakUntrustedText()
    {
        foreach (var version in new[] { "", "latest", "file:///private", "1.2\nsecret", new string('x', 97) })
            Equal<string?>(null, ApplicationRuntimeFactsReader.NormalizeVersion(version));
        Equal("1.2.3-beta+7", ApplicationRuntimeFactsReader.NormalizeVersion(" 1.2.3-beta+7 "));
        Equal("https://example.invalid:8443", ApplicationRuntimeFactsReader.SafeOrigin(
            "https://username:password@example.invalid:8443/private/token?secret=value#token"));
        foreach (var uri in new[] { "file:///private", "ftp://example.invalid", "not a uri", "//example.invalid" })
            Equal<string?>(null, ApplicationRuntimeFactsReader.SafeOrigin(uri));
        return Task.CompletedTask;
    }

    internal static async Task BridgeIsAccountlessReadOnlyAndStrict()
    {
        var root = TempRoot();
        try
        {
            using var dispatcher = new RuntimeFactsBridgeDispatcher(new(root, null), () => 4);
            Equal(false, BridgeRequestPolicy.RequiresAccountContext(RuntimeFactsBridgeDispatcher.RequestName));
            var result = (await dispatcher.DispatchAsync(Request())).Response;
            Equal("ok", result.Status);
            Equal<BridgeAccountContext?>(null, result.AccountContext);
            Equal(6, result.Payload.EnumerateObject().Count());
            Equal(JsonValueKind.Null, result.Payload.GetProperty("applicationVersion").ValueKind);
            Equal(root, result.Payload.GetProperty("dataDirectory").GetString());
            foreach (var invalid in new[]
            {
                Request(new { schemaVersion = 1, path = root }),
                Request(new { schemaVersion = "1" }),
                Request(new { schemaVersion = 2 }),
                Request() with { AccountContext = new("test", "scm", "synthetic") },
                Request() with { Name = "diagnostics.deleteFiles" },
            })
            {
                var response = (await dispatcher.DispatchAsync(invalid)).Response;
                Equal("error", response.Status);
                Equal(false, response.Payload.GetRawText().Contains(root));
            }
        }
        finally { Directory.Delete(root, true); }
    }

    internal static async Task StaleCancelledAndDisposedNeverReturnFacts()
    {
        var root = TempRoot();
        try
        {
            long generation = 4;
            using var dispatcher = new RuntimeFactsBridgeDispatcher(
                new(root, null, () => { generation++; return "https://example.invalid"; }), () => generation);
            Equal("error", (await dispatcher.DispatchAsync(Request())).Response.Status);
            Equal("error", (await dispatcher.DispatchAsync(Request())).Response.Status);
            using var cts = new CancellationTokenSource();
            cts.Cancel();
            Equal(BridgeResponseStatuses.Cancelled, (await dispatcher.DispatchAsync(Request(), cts.Token)).Response.Status);
            dispatcher.Dispose();
            Equal("error", (await dispatcher.DispatchAsync(Request() with { SessionGeneration = generation })).Response.Status);
        }
        finally { Directory.Delete(root, true); }
    }

    internal static Task MissingMetadataDoesNotHideOtherFacts()
    {
        var root = TempRoot();
        try
        {
            var exe = Path.Combine(root, "client.exe");
            File.WriteAllText(exe, "synthetic");
            Directory.CreateDirectory(Path.Combine(root, "Images"));
            var reader = new ApplicationRuntimeFactsReader(root, exe,
                () => throw new IOException("private server configuration"),
                _ => throw new IOException("private exe path"));
            var result = reader.Read();
            Equal<string?>(null, result.ApplicationVersion);
            Equal<string?>(null, result.ServerOrigin);
            Equal(true, result.ImageCacheExists);
            Equal(root, result.DataDirectory);
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }

    private static BridgeEnvelope Request(object? body = null) => BridgeEnvelope.Request(
        RuntimeFactsBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 4, body ?? new { schemaVersion = 1 });

    private static string TempRoot() => Directory.CreateTempSubdirectory("starbridge-runtime-facts-").FullName;

    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"Expected {expected}, actual {actual}");
    }
}
