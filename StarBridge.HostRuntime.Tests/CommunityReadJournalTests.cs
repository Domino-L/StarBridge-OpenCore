using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;

internal static class CommunityReadJournalTests
{
    internal static async Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-community-diagnostic-" + Guid.NewGuid().ToString("N"));
        try
        {
            var journal = new CommunityReadJournal(root);
            journal.Record("bridge", "secret-token\nprivate-account", 999, -1);
            journal.Record("publication-gate", "cancelled", null, 12000);
            journal.Record("workspace-http", "http-error", 403, 2);
            journal.Record("workspace-media-http", "http-error", 403, 1);
            journal.Record("chat-read-receipt", "cursor-mismatch", 200, 5);
            journal.Record("chat-read-receipt", "secret-channel-and-message", 200, 1);
            foreach (var stage in new[] { "workspace-membership-http", "workspace-snapshot-http", "workspace-session-http" })
                journal.Record(stage, "http-error", 403, 1);
            journal.Record("publication-send", "privacy_publication.identity_required", 409, 3);
            using var writer = new PrivacyRelayWriter(new Uri("http://localhost:5058"), new Denied());
            writer.CommunityReadDiagnostic = journal.Record;
            try { await writer.ReadCommunityTargetsAsync("secret-token", default); throw new Exception("Expected denial"); }
            catch (AccountBridgeHostException error) when (error.Code == "privacy_publication.identity_unavailable") { }
            using var unavailable = new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) {
                Content = new StringContent("{\"code\":\"SCM_BUSINESS_IDENTITY_UNAVAILABLE\",\"message\":\"private-account secret-token\"}")
            };
            await writer.RecordPublicationErrorAsync(unavailable, default);
            using var arbitrary = new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) {
                Content = new StringContent("{\"code\":\"secret-token\"}")
            };
            await writer.RecordPublicationErrorAsync(arbitrary, default);
            var path = Path.Combine(root, "community-read-diagnostics.log");
            var content = File.ReadAllText(path);
            foreach (var stage in new[] { "workspace-membership-http", "workspace-snapshot-http", "workspace-session-http" })
                Check(content.Contains($"stage={stage} code=http-error status=403"), "legacy route diagnostics are allowlisted");
            Check(content.Contains("stage=workspace-http code=http-error status=403") &&
                content.Contains("stage=workspace-media-http code=http-error status=403"), "route classes survive strict local filtering");
            Check(content.Contains("stage=relay code=privacy_publication.identity_unavailable status=401"), "HTTP status and mapped error");
            Check(content.Contains("stage=publication-http code=scm_business_identity_unavailable status=503") &&
                content.Contains("stage=publication-http code=unclassified status=503"), "only allowlisted server codes are recorded");
            Check(content.Contains("stage=bridge code=unclassified status=none elapsedMs=0"), "strict field filtering");
            Check(content.Contains("stage=chat-read-receipt code=cursor-mismatch status=200") &&
                content.Contains("stage=chat-read-receipt code=unclassified status=200"), "receipt reason allowlist never accepts arbitrary data");
            Check(content.Contains("stage=publication-gate code=cancelled status=none elapsedMs=12000") &&
                content.Contains("stage=publication-send code=privacy_publication.identity_required status=409"),
                "publication phases distinguish local queue deadlines and server identity rejection");
            Check(!content.Contains("secret") && !content.Contains("private-account") && !content.Contains("localhost"), "no sensitive values");
            writer.CommunityReadDiagnostic = (_, _, _, _) => throw new IOException("synthetic failure");
            try { await writer.ReadCommunityTargetsAsync("secret-token", default); throw new Exception("Expected denial"); }
            catch (AccountBridgeHostException error) when (error.Code == "privacy_publication.identity_unavailable") { }
            File.WriteAllText(path, new string('x', 128 * 1024));
            journal.Record("bridge", "ok", null, 1);
            Check(new FileInfo(path).Length < 1024, "bounded file");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
    private sealed class Denied : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(new HttpResponseMessage(HttpStatusCode.Unauthorized)
                { Content = new StringContent("private-account secret-token") });
    }
}
