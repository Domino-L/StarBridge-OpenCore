namespace StarBridge.HostRuntime.Account;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.TrustSafety;

internal sealed partial class AccountSafetyClient
{
    internal async Task<object> AppealAsync(string bearer, CreateSanctionAppealRequestContract input,
        Action current, CancellationToken token)
    {
        // Refresh ownership before sending; no target/account identity is supplied by Flutter.
        var before = await ReadAsync(bearer, token);
        current();
        if (!before.Sanctions.Any(item => item.SanctionId == input.SanctionId))
            throw new AccountBridgeHostException("accountSafety.target_unavailable");
        if (before.Appeals.Any(item => item.SanctionId == input.SanctionId))
            return new { schemaVersion = 1, outcome = "alreadySubmitted" };
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/appeals"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Content = JsonContent.Create(input, options: Json);
        token.ThrowIfCancellationRequested();
        current();
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.NotFound or HttpStatusCode.TooManyRequests)
                throw new AccountBridgeHostException("accountSafety.rejected");
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                throw new AccountBridgeHostException("accountSafety.forbidden");
            if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > MaximumBytes) throw Unknown();
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) != 0)
            {
                if (buffer.Length + count > MaximumBytes) throw Unknown();
                buffer.Write(chunk, 0, count);
            }
            using var document = Document(buffer.ToArray());
            var receipt = document.RootElement.Deserialize<SanctionAppealRecordContract>(Json);
            if (receipt is null || string.IsNullOrWhiteSpace(receipt.AppealId) ||
                receipt.SanctionId != input.SanctionId || receipt.Details != input.Details ||
                !SanctionAppealStatuses.IsSupported(receipt.Status) || receipt.CreatedAt == default)
                throw Unknown();
            current();
            return new { schemaVersion = 1, outcome = "submitted" };
        }
        catch (AccountBridgeHostException error) when (error.Code == "accountSafety.data_invalid") { throw Unknown(); }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { throw Unknown(); }
    }
    private static AccountBridgeHostException Unknown() => new("accountSafety.outcome_unknown");
}
