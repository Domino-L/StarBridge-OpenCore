namespace StarBridge.HostRuntime.Account;

using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.TrustSafety;

internal sealed partial class AccountSafetyClient
{
    internal async Task<NotificationInboxContract> ReadInboxAsync(string bearer, CancellationToken token)
    {
        var bytes = await GetAsync("/api/notifications", bearer, token);
        using var document = Document(bytes);
        var inbox = document.RootElement.Deserialize<NotificationInboxContract>(Json)
            ?? throw Invalid();
        if (inbox.Items is null || inbox.Items.Length > 5000 ||
            inbox.Items.Any(x => x is null || string.IsNullOrWhiteSpace(x.NotificationId) ||
                x.NotificationId.Length > 1024 || x.Title is null || x.Title.Length > 2000 ||
                x.Body is null || x.Body.Length > 20000 || x.Category is null ||
                x.Priority is null || x.ActionTarget is null || x.ActionLabel is null) ||
            inbox.Items.Select(x => x.NotificationId).Distinct(StringComparer.Ordinal).Count() != inbox.Items.Length)
            throw Invalid();
        return inbox;
    }

    internal async Task MarkInboxReadAsync(string bearer, string[] ids, Action current, CancellationToken token)
    {
        current();
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/notifications/read"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Content = JsonContent.Create(new NotificationReadRequestContract(ids));
        // Never replay a write after an uncertain response.
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        current();
        if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("notificationInbox.write_unavailable");
        await response.Content.LoadIntoBufferAsync(4096);
        var receipt = await response.Content.ReadFromJsonAsync<NotificationReadResponseContract>(Json, token);
        current();
        if (receipt is null || receipt.UpdatedCount < 0 || receipt.UpdatedCount > ids.Length || receipt.ReadAt == default)
            throw new AccountBridgeHostException("notificationInbox.write_unavailable");
    }
}
