using System.Net;
using StarBridge.HostRuntime.Auth;

internal static class IdentityLinkProofOutageTests
{
    internal static async Task Verify()
    {
        var scm = new ScmHttpClient();
        using var http = new HttpClient(new UnavailableProof());
        var client = new IdentityLinkClient(scm, http, ScmOAuthOptions.CreateDefault(),
            () => new Uri("https://synthetic.invalid/"));
        try
        {
            await client.RequestLegacyProofAsync(
                new("challenge", "nonce", "audience", "issuer", "subject", DateTimeOffset.UtcNow.AddMinutes(1)),
                new LegacyIdentityLinkPasswordCredential("synthetic", "synthetic"), default);
            throw new Exception("Proof outage was treated as success");
        }
        catch (HttpRequestException error)
        {
            if (error.GetType().Name != "LegacyIdentityLinkProofUnavailableException" ||
                error.StatusCode != HttpStatusCode.ServiceUnavailable)
                throw new Exception("Proof 503 must retain a distinct proof-service-unavailable classification");
        }
    }

    private sealed class UnavailableProof : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri?.AbsolutePath != "/api/auth/identity-link/proof")
                throw new Exception("Unexpected route");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        }
    }
}
