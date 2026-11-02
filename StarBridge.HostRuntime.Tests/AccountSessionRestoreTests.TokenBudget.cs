using System.Net;
using System.Text;
using StarBridge.HostRuntime.Auth;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task TokenReadBudget()
    {
        foreach (var status in new[] { HttpStatusCode.OK, HttpStatusCode.Unauthorized })
        foreach (var declared in new[] { false, true })
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var vault = new RaceVault();
            var key = options.AuthorityId + ":subject-1";
            vault.SaveRefreshToken(key, "synthetic-refresh");
            var prefix = status == HttpStatusCode.OK
                ? "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}"
                : "{\"error\":\"invalid_grant\"}";
            var content = new BudgetContent(Encoding.UTF8.GetBytes(prefix.PadRight(2 * 65536)), declared);
            using var handler = new ScriptedHandler(request => {
                AssertEqual(options.TokenEndpoint, request.RequestUri, "oversize token response must not read identity");
                return new HttpResponseMessage(status) { Content = content };
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            try { await oauth.TryRestoreSessionAsync(default); throw new InvalidOperationException("Oversize response accepted"); }
            catch (ScmRefreshTemporarilyUnavailableException) { }
            AssertEqual(0, content.Serializations, "headers-only HTTP must not prebuffer the response");
            AssertEqual(declared ? 0L : 65537L, content.Stream.BytesRead, "stream read budget including one-byte overflow probe");
            AssertEqual(0, vault.Deletes, "oversize body is never authoritative rejection");
            AssertEqual(key, vault.LoadActiveAccountKey(), "oversize response keeps selection");
            AssertEqual(ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable, oauth.LastSessionRestoreOutcome, "oversize is retryable");
            Console.WriteLine($"CX-L07 token budget status={(int)status} declared={declared} bytes={content.Stream.BytesRead} deletes=0");
        }
        // The limit is inclusive, not a character-count approximation.
        var exactOptions = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var exactVault = new RaceVault();
        exactVault.SaveRefreshToken(exactOptions.AuthorityId + ":subject-1", "synthetic-refresh");
        var exact = new BudgetContent(Encoding.UTF8.GetBytes(
            "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}".PadRight(65536)), false);
        using var exactHandler = new ScriptedHandler(request => request.RequestUri == exactOptions.TokenEndpoint
            ? new HttpResponseMessage(HttpStatusCode.OK) { Content = exact }
            : JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\"}"));
        var exactOauth = new OAuthPkceClient(new ScmHttpClient(exactHandler), exactVault, exactOptions);
        AssertEqual(true, await exactOauth.TryRestoreSessionAsync(default) is not null, "exact 64 KiB token body accepted");
        AssertEqual(65536L, exact.Stream.BytesRead, "exact budget stream count");
    }

    private sealed class BudgetContent : HttpContent
    {
        internal CountingStream Stream { get; }
        internal int Serializations { get; private set; }
        internal BudgetContent(byte[] body, bool declared)
        {
            Stream = new CountingStream(body);
            Headers.ContentType = new("application/json");
            if (declared) Headers.ContentLength = body.Length;
        }
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        {
            Serializations++;
            throw new InvalidOperationException("Token response was buffered before the budget check");
        }
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromResult<Stream>(Stream);
        protected override Task<Stream> CreateContentReadStreamAsync(CancellationToken token) => Task.FromResult<Stream>(Stream);
    }

    private sealed class CountingStream(byte[] body) : MemoryStream(body, writable: false)
    {
        internal long BytesRead { get; private set; }
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default)
        {
            token.ThrowIfCancellationRequested();
            var read = base.Read(buffer.Span);
            BytesRead += read;
            return ValueTask.FromResult(read);
        }
    }
}
