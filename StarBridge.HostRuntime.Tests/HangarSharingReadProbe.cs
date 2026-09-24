using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;

// Opt-in read-only replay of the actual editor. No session restoration, credential
// writes, response bodies, organization names or identifiers are logged.
internal static class HangarSharingReadProbe
{
    internal static async Task<int> Run()
    {
        try
        {
            var origin = new Uri("https://api.scstarbridge.com/");
            // Match the running acceptance client's environment selection. Never
            // scan other environment stores or restore/migrate an old session.
            var settings = ScmEnvironmentSettings.Load();
            if (!settings.AccountAccessEnabled || settings.RelayBaseUri != origin)
                throw new InvalidOperationException("Read probe environment does not match the approved origin.");
            var suffix = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(origin.AbsoluteUri)))[..16];
            var store = new WindowsLegacyMigrationCredentialStore(Path.Combine(HostDataRoot.CurrentRoot,
                settings.LegacyMigrationCredentialFileName + ".active-" + suffix + ".dat"));
            var credential = store.Load();
            if (credential is null) { Console.WriteLine("FAIL|sharing-editor|credential-absent"); return 1; }
            using var handler = new ReadOnlyHandler(origin);
            using var client = new CommunityClient(origin, handler);
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(45));
            var timer = Stopwatch.StartNew();
            var editor = JsonSerializer.SerializeToElement(await client.ReadHangarSharingAsync(
                credential.AuthToken, JsonSerializer.SerializeToElement(new { schemaVersion = 1 }),
                "sharing-editor-read-probe", () => { }, deadline.Token, legacyViewerId: credential.AccountId));
            if (editor.GetProperty("options").GetArrayLength() == 0) throw new InvalidDataException();
            Console.WriteLine($"PASS|sharing-editor|elapsed-ms={timer.ElapsedMilliseconds}|writes=0");
            return 0;
        }
        catch (Exception error)
        {
            Console.WriteLine($"FAIL|sharing-editor|type={error.GetType().Name}|code={(error as AccountBridgeHostException)?.Code}|details-suppressed");
            return 1;
        }
    }

    private sealed class ReadOnlyHandler(Uri origin) : DelegatingHandler(new HttpClientHandler { AllowAutoRedirect = false })
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            if (request.Method != HttpMethod.Get || request.Content is not null || uri.Authority != origin.Authority ||
                uri.Scheme != origin.Scheme || uri.Query.Length != 0 || uri.AbsolutePath is not
                ("/api/fleets/hangar-sharing" or "/api/fleets/membership" or "/api/fleets" or "/api/auth/session"))
                throw new InvalidOperationException("Read probe rejected an out-of-scope request.");
            var timer = Stopwatch.StartNew();
            var response = await base.SendAsync(request, token);
            Console.WriteLine($"READ|{uri.AbsolutePath}|http={(int)response.StatusCode}|headers-ms={timer.ElapsedMilliseconds}");
            return response;
        }
    }
}
