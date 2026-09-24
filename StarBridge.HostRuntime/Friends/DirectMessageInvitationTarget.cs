using StarBridge.HostRuntime.Communities;
using System.Net.Http.Headers;
using System.Text.Json;

namespace StarBridge.HostRuntime.Friends;

internal sealed partial class FriendsReader
{
    // Target comes only from this account's protected outbox, not Bridge JSON.
    internal async Task<InvitationDeliveryTarget> RebindInvitationTargetAsync(string bearer, string accountId,
        string scope, CancellationToken token)
    {
        try
        {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin,
            "/api/friends/chat/messages?targetAccountId=" + Uri.EscapeDataString(accountId) + "&limit=1"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (!response.IsSuccessStatusCode) throw ChatError("target_changed");
        using var document = JsonDocument.Parse(await CommandBody(response, deadline.Token));
        var root = document.RootElement;
        RejectDuplicates(root);
        if (Text(root, "targetAccountId", 256) != accountId) throw ChatError("data_invalid");
        return new("private", accountId, scope, _origin);
        }
        catch (Exception error) when (error is HttpRequestException or IOException) { throw ChatError("unavailable"); }
        catch (JsonException) { throw ChatError("data_invalid"); }
    }
    internal InvitationDeliveryTarget ResolveInvitationTarget(string bearer, string reference, string scope)
    {
        lock (_targetGate)
        {
            if (!_conversations.TryGetValue(reference, out var target) || target.Owner != Owner(bearer, scope)
                || target.Expires < DateTimeOffset.UtcNow) throw ChatError("target_changed");
            return new("private", target.Id, scope, _origin, target.DisplayName);
        }
    }
}
