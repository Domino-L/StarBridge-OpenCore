using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;

// Opt-in, bounded authenticated GET diagnostics. Never prints identifiers,
// credentials, raw payloads or media. Never publishes or changes sharing.
internal static class WpfCommunityShipsProbe
{
    internal static async Task<int> Run()
    {
        try
        {
            var origin = new Uri("https://api.scstarbridge.com/");
            var suffix = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(origin.AbsoluteUri)))[..16];
            var store = new WindowsLegacyMigrationCredentialStore(Path.Combine(HostDataRoot.CurrentRoot,
                "legacy-migration-credential.development.dat.active-" + suffix + ".dat"));
            var credential = store.Load();
            if (credential is null) { Console.WriteLine("FAIL|active-credential-absent"); return 1; }
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(60));
            using var http = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false });
            async Task<JsonElement?> Read(string path, bool optional = false)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(origin, path));
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
                using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                Console.WriteLine($"HTTP|{path}|{(int)response.StatusCode}");
                if (!response.IsSuccessStatusCode && optional) return null;
                response.EnsureSuccessStatusCode();
                await response.Content.LoadIntoBufferAsync(8 * 1024 * 1024);
                using var json = JsonDocument.Parse(await response.Content.ReadAsByteArrayAsync(deadline.Token));
                return json.RootElement.Clone();
            }
            var session = (await Read("api/auth/session"))!.Value;
            if (Text(session, "accountId") != credential.AccountId) throw new InvalidDataException();
            var membership = (await Read("api/fleets/membership"))!.Value;
            var code = Text(membership, "fleetCode");
            var fleets = (await Read("api/fleets"))!.Value;
            var fleet = fleets.EnumerateArray().Single(row => string.Equals(Text(row, "code"), code, StringComparison.OrdinalIgnoreCase));
            var members = fleet.GetProperty("members").EnumerateArray().ToArray();
            var ships = fleet.GetProperty("ships").EnumerateArray().ToArray();
            var matched = ships.Count(ship => members.Any(member =>
                !string.IsNullOrEmpty(Text(ship, "ownerAccountId")) &&
                string.Equals(Text(ship, "ownerAccountId"), Text(member, "accountId"), StringComparison.OrdinalIgnoreCase)));
            Console.WriteLine($"READ|raw-snapshot|members={members.Length}|ships={ships.Length}|stable-owner-matches={matched}|owner-id-missing={ships.Count(ship => string.IsNullOrEmpty(Text(ship, "ownerAccountId")))}");
            var players = await Read("api/players", optional: true);
            if (players is { ValueKind: JsonValueKind.Array } playerRows)
            {
                var self = playerRows.EnumerateArray().Where(row => string.Equals(Text(row, "accountId"), credential.AccountId, StringComparison.OrdinalIgnoreCase)).ToArray();
                Console.WriteLine($"READ|self-player|rows={self.Length}");
                foreach (var row in self)
                    Console.WriteLine($"READ|self-player-inventory|ships={(row.TryGetProperty("ownedShips", out var inventory) && inventory.ValueKind == JsonValueKind.Array ? inventory.GetArrayLength() : -1)}|shared={(row.TryGetProperty("personalHangarSharedWithFleet", out var shared) && shared.ValueKind == JsonValueKind.True)}|online={(row.TryGetProperty("online", out var online) && online.ValueKind == JsonValueKind.True)}");
            }
            var sharing = await Read("api/fleets/hangar-sharing", optional: true);
            if (sharing is { } consent)
                Console.WriteLine($"READ|sharing|explicit={consent.GetProperty("usesExplicitTargets").GetBoolean()}|selected={consent.GetProperty("selectedCodes").GetArrayLength()}|current-selected={consent.GetProperty("selectedCodes").EnumerateArray().Any(item => string.Equals(item.GetString(), code, StringComparison.OrdinalIgnoreCase))}");
            using var client = new CommunityClient(origin);
            var mine = await client.ReadWpfS2Async(credential.AuthToken, new("mine", "", null, null), "ship-read-probe", credential.AccountId, deadline.Token);
            if (mine.Items.Length != 1) throw new InvalidDataException();
            var result = JsonSerializer.SerializeToElement(await client.ReadShipsAsync(credential.AuthToken,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = mine.Items.Single().TargetRef, offset = 0,
                    query = new { text = "", filter = "all", sort = "spec", descending = true, culture = "zh-CN" } }),
                "ship-read-probe", () => { }, deadline.Token));
            var count = result.GetProperty("totalCount").GetInt32();
            Console.WriteLine($"READ|adapter-ships|count={count}");
            if (sharing is not null)
            {
                var editor = JsonSerializer.SerializeToElement(await client.ReadHangarSharingAsync(
                    credential.AuthToken, JsonSerializer.SerializeToElement(new { schemaVersion = 1 }),
                    "ship-read-probe", () => { }, deadline.Token, legacyViewerId: credential.AccountId));
                Console.WriteLine($"PASS|legacy-sharing-editor|options={editor.GetProperty("options").GetArrayLength()}");
            }
            Console.WriteLine(count > 0 ? "PASS|nonempty-organization-ships" : ships.Length == 0 ? "FAIL|upstream-snapshot-empty" : "FAIL|adapter-owner-projection-empty");
            return count > 0 ? 0 : 1;
        }
        catch (Exception e)
        {
            Console.WriteLine($"FAIL|ship-read-probe|type={e.GetType().Name}|details-suppressed");
            return 1;
        }
    }

    private static string? Text(JsonElement row, string key) => row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
