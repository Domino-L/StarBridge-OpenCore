using System.Net.Http;
using System.Security.Authentication;
using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Observe only the token hop. A rejected grant is not a connectivity failure.
    // Callers validate the complete token contract before any vault mutation.
    private async Task<HttpResponseMessage> SendRouteTokenRequestAsync(HttpRequestMessage request,
        CancellationToken token, CancellationToken callerToken)
    {
        HttpResponseMessage? response = null;
        try
        {
            response = await scmHttpClient.SendAsync(request, cancellationToken: token,
                requestTimeout: TokenRequestTimeout, completionOption: HttpCompletionOption.ResponseHeadersRead);
            if ((int)response.StatusCode >= 500) RouteState?.LoginNetworkFailed();
            await BoundTokenResponseAsync(response, token);
            // Detect domestic HTML/gateway bodies on both success and error statuses.
            // The overseas token parser and its exception behavior remain unchanged.
            if (RouteState?.IsDomestic == true)
            {
                using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
            }
            return response;
        }
        catch (Exception exception)
        {
            response?.Dispose();
            if (!callerToken.IsCancellationRequested && (exception is JsonException or IOException or AuthenticationException ||
                exception is HttpRequestException http && (http.StatusCode is null || (int)http.StatusCode >= 500) ||
                exception is OperationCanceledException))
                RouteState?.LoginNetworkFailed();
            throw;
        }
    }
}
