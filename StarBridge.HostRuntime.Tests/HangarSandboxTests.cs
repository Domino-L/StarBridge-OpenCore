using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;
using System.Net;

internal static class HangarSandboxTests
{
    public static async Task LiveProbe()
    {
        using var dispatcher = HangarSandboxDispatcher.FromEnvironment(() => 0) ?? throw new Exception("Sandbox not enabled");
        var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "live-a", 0, new { testAccount = "A" }));
        if (read.Response.Status != "ok" || read.Response.Payload.GetProperty("ships").GetArrayLength() != 3)
            throw new Exception("MySQL data did not reach Host");
        var name = read.Response.Payload.GetProperty("ships")[0].GetProperty("presentation").GetProperty("names").GetProperty("zhHans").GetString();
        if (string.IsNullOrWhiteSpace(name)) throw new Exception("Chinese presentation missing");
        var other = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "live-b", 0, new { testAccount = "B" }));
        if (other.Response.Status != "ok" || other.Response.Payload.GetProperty("revision").GetInt32() != 0)
            throw new Exception("Test account isolation failed");
        Console.WriteLine("PASS|Host-Java-MySQL|3-ships|Chinese-names|A-B-isolation");
    }
    public static async Task GuardsAndProjection()
    {
        using var http = new HttpClient(new Handler());
        using var dispatcher = new HangarSandboxDispatcher(http, new string('a', 64), new string('b', 64), () => 5);
        var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "read", 5, new { testAccount = "A" }));
        if (read.Response.Status != "ok" || read.Response.Payload.GetProperty("ships").GetArrayLength() != 0)
            throw new Exception("Read projection missing");
        var bad = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "bad", 4, new { testAccount = "A" }));
        if (bad.Response.Status != "error") throw new Exception("Stale request accepted");
        var owner = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "owner", 5, new { testAccount = "A", owner = "real" }));
        if (owner.Response.Status != "error") throw new Exception("Unknown owner accepted");
    }
    public static Task LocationFromEnvironmentOnly()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-HangarSandbox-" + Guid.NewGuid().ToString("N"));
        try
        {
            HangarSandboxLocation? Resolve(string? on, string? folder, out string? refusal) =>
                HangarSandboxLocation.Resolve(name => name switch
                {
                    HangarSandboxLocation.SwitchVariable => on,
                    HangarSandboxLocation.RootVariable => folder,
                    _ => throw new Exception("Unexpected variable " + name)
                }, out refusal);
            void Refused(string? on, string? folder, string expected)
            {
                if (Resolve(on, folder, out var refusal) is not null) throw new Exception("Sandbox opened: " + expected);
                if (refusal is null || !refusal.Contains(expected, StringComparison.Ordinal))
                    throw new Exception("Wrong refusal for " + expected + ": " + refusal);
                if (folder is { Length: > 0 } && refusal.Contains(folder, StringComparison.OrdinalIgnoreCase))
                    throw new Exception("Refusal leaked the folder");
            }

            // Not asked for: no sandbox and nothing to report, whatever the folder says.
            foreach (var off in new string?[] { null, "", "0", "true" })
                if (Resolve(off, root, out var quiet) is not null || quiet is not null)
                    throw new Exception("Sandbox opened without STARBRIDGE_HANGAR_SANDBOX=1");
            Refused("1", null, "is not set");
            Refused("1", "   ", "is not set");
            Refused("1", Path.Combine("relative", "sandbox"), "not an absolute path");
            // UsePreparedRoot would expand %VAR%, so the data root could leave the checked folder.
            Refused("1", Path.Combine(root, "%TEMP%"), "must not contain %");
            Refused("1", root, "client-data is missing");
            Directory.CreateDirectory(Path.Combine(root, "client-data"));
            Refused("1", root, "client.dpapi is missing");
            File.WriteAllBytes(Path.Combine(root, "client.dpapi"), [1]);

            var location = Resolve("1", root + Path.DirectorySeparatorChar, out var none)
                ?? throw new Exception("Prepared sandbox folder refused: " + none);
            if (none is not null || location.DataRoot != Path.Combine(root, "client-data") ||
                location.Manifest != Path.Combine(root, "client.dpapi"))
                throw new Exception("Sandbox folder resolved wrongly");

            var bootstrap = Path.Combine(root, "bootstrap");
            HangarSandboxLocation.ReportRefusal(bootstrap, "STARBRIDGE_HANGAR_SANDBOX_ROOT is not set");
            var log = File.ReadAllText(Path.Combine(bootstrap, "hangar-sandbox-diagnostics.log"));
            if (!log.Contains("hangar sandbox off: STARBRIDGE_HANGAR_SANDBOX_ROOT is not set", StringComparison.Ordinal))
                throw new Exception("Refusal was not logged");
            // An unwritable bootstrap folder must not stop the Host.
            HangarSandboxLocation.ReportRefusal(Path.Combine(root, "client.dpapi", "nested"), "unwritable");

            // The source carries no developer folder any more.
            var source = File.ReadAllText(Path.Combine(FindRepositoryRoot(), "StarBridge.HostRuntime", "Hangar", "HangarSandboxDispatcher.cs"));
            if (source.Contains(@":\", StringComparison.Ordinal)) throw new Exception("Dispatcher still names a local folder");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
        return Task.CompletedTask;
    }

    private static string FindRepositoryRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, "StarBridge.HostRuntime", "Hangar", "HangarSandboxDispatcher.cs")))
                return directory.FullName;
        throw new Exception("Repository root not found");
    }

    private sealed class Handler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (request.RequestUri?.AbsoluteUri != "http://127.0.0.1:18083/hangar" ||
                request.Headers.Authorization?.Parameter != new string('a', 64)) throw new Exception("Wrong destination");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent("{\"revision\":0,\"savedAt\":null,\"catalogVersion\":null,\"ships\":[]}") });
        }
    }
}
