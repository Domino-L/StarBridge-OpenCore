using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;

// Explicit production read diagnostics only (including POST read query). No login, publication, policy write,
// identifier output, or second Native Host process.
internal static class CommunitySharingReadProbe
{
    internal static async Task<int> Run()
    {
        var stage = "credential";
        try
        {
            var origin = new Uri("https://api.scstarbridge.com/");
            var suffix = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(origin.AbsoluteUri)))[..16];
            var store = new WindowsLegacyMigrationCredentialStore(Path.Combine(HostDataRoot.CurrentRoot,
                "legacy-migration-credential.development.dat.active-" + suffix + ".dat"));
            var credential = store.Load();
            if (credential is null)
            {
                Console.WriteLine("FAIL|community-sharing-read|active-credential-absent");
                return 1;
            }
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            using var handler = new ReadOnlyHandler(origin);
            using var sessionClient = new HttpClient(handler, disposeHandler: false);
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(origin, "/api/auth/session"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
            stage = "session";
            using var response = await sessionClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            response.EnsureSuccessStatusCode();
            // Legacy session responses may include bounded account media.
            // Match the existing opt-in probes, without writing or logging it.
            stage = "session-buffer";
            await response.Content.LoadIntoBufferAsync(8 * 1024 * 1024);
            stage = "session-identity";
            using var session = JsonDocument.Parse(await response.Content.ReadAsByteArrayAsync(deadline.Token));
            if (session.RootElement.GetProperty("accountId").GetString() != credential.AccountId)
                throw new InvalidDataException("Active session mismatch.");
            using var writer = new PrivacyRelayWriter(origin, handler);
            stage = "targets-first";
            var first = await writer.ReadCommunityTargetsAsync(credential.AuthToken, deadline.Token);
            stage = "targets-second";
            var second = await writer.ReadCommunityTargetsAsync(credential.AuthToken, deadline.Token);
            var stable = first.Communities.Select(row => (row.Code, row.JoinedAt))
                .SequenceEqual(second.Communities.Select(row => (row.Code, row.JoinedAt)));
            if (!stable) throw new InvalidDataException("Membership changed during probe.");
            stage = "member-directory";
            var memberCount = 0;
            foreach (var target in second.Communities)
            {
                var scope = new CommunityRealtimeScope(target.Code, target.JoinedAt, 0, false, false, [], []);
                var offset = 0;
                string? revision = null;
                var identities = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                do
                {
                    var page = await writer.ReadCommunityMembersAsync(credential.AuthToken,
                        new CommunityMemberDirectoryRequest(3, scope, offset, revision), deadline.Token);
                    if (page.Members.Any(member => !identities.Add(member.AccountId)))
                        throw new InvalidDataException("Duplicate member across pages.");
                    offset += page.Members.Length;
                    revision = page.Revision;
                    if (offset == page.Total) break;
                } while (true);
                memberCount += identities.Count;
            }
            Console.WriteLine("PASS|community-sharing-read|authenticated-session-matched");
            Console.WriteLine($"PASS|community-sharing-read|schema={second.SchemaVersion}|organizations={second.Communities.Length}|primary-present={second.PrimaryFleetCode is not null}|membership-stable=true");
            Console.WriteLine($"PASS|community-sharing-read|members={memberCount}|directory-schema=3|pages={handler.MemberReads}");
            Console.WriteLine($"PASS|community-sharing-read|GET={handler.Reads}|writes=0|identifiers-and-content-suppressed");
            return 0;
        }
        catch (Exception error)
        {
            var status = error is HttpRequestException http ? (int?)http.StatusCode : null;
            var category = error is HttpRequestException requestError ? requestError.HttpRequestError.ToString() : "none";
            var socket = error.InnerException as System.Net.Sockets.SocketException;
            Console.WriteLine($"FAIL|community-sharing-read|stage={stage}|type={error.GetType().Name}|http={status}|category={category}|inner={error.InnerException?.GetType().Name}|socket={socket?.SocketErrorCode}|details-suppressed");
            return 1;
        }
    }

    private sealed class ReadOnlyHandler(Uri origin) : DelegatingHandler(
        new HttpClientHandler { AllowAutoRedirect = false })
    {
        internal int Reads { get; private set; }
        internal int MemberReads { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri is not { } uri || uri.Scheme != origin.Scheme ||
                uri.Authority != origin.Authority || uri.Query.Length != 0)
                throw new InvalidOperationException("Read probe rejected an out-of-scope request.");
            if (request.Method == HttpMethod.Get && request.Content is null &&
                uri.AbsolutePath is "/api/auth/session" or "/api/privacy/community-scopes") Reads++;
            else if (request.Method == HttpMethod.Post && uri.AbsolutePath == "/api/privacy/community-members/read")
            {
                var input = JsonSerializer.Deserialize<CommunityMemberDirectoryRequest>(
                    await request.Content!.ReadAsStringAsync(token), LocalPrivacyStore.Json)!;
                PrivacyRelayWriter.ValidateMemberRequest(input);
                if (input.Scope.Fields != 0 || input.Scope.AllMembersCanView || input.Scope.AdministratorsCanView ||
                    input.Scope.VisibilityGroupIds.Length != 0 || input.Scope.MemberOverrides is not { Length: 0 })
                    throw new InvalidOperationException("Read probe rejects permission-bearing input.");
                MemberReads++;
            }
            else throw new InvalidOperationException("Read probe rejected a mutation.");
            return await base.SendAsync(request, token);
        }
    }
}
