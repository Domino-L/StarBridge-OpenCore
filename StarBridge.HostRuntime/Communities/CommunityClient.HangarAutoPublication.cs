using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Import may update only an existing explicit audience. Never infer consent
    // from the selected page, directory membership or the old sharing boolean.
    internal async Task<CommunityCommand> UpdateSharedHangarAsync(string bearer, Action current,
        Func<CommunityPublishedShip[]> inventorySource, CancellationToken token)
    {
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        try
        {
            current();
            var inventory = inventorySource();
            var consent = await ReadHangarConsent(bearer, token);
            current();
            if (!consent.Explicit || consent.Codes.Length == 0) return new("accepted");
            using var request = new HttpRequestMessage(HttpMethod.Put, new Uri(_origin, HangarSharingPath + "/publish"))
            {
                Content = JsonContent.Create(new { schemaVersion = 1, version = consent.Version,
                    selectedCodes = consent.Codes, ships = inventory })
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            token.ThrowIfCancellationRequested();
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode != HttpStatusCode.OK)
                return new(response.StatusCode == HttpStatusCode.Conflict ? "rejected" : "unknown", "refreshRequired");
            var saved = await ParseHangarResponse(response, deadline.Token, inventory.Length);
            current();
            return saved.Explicit && saved.Version != consent.Version && saved.Codes.SequenceEqual(consent.Codes)
                ? new("accepted") : new("unknown", "outcomeUnknown");
        }
        catch (LocalHangarStoreException) { return new("rejected", "localHangarRequired"); }
        catch (AccountBridgeHostException e) when (!sent && e.Code == "communities.unavailable" && e.Retryable)
        { return new("rejected", token.IsCancellationRequested ? "cancelled" : "unavailable"); }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" :
            token.IsCancellationRequested ? "cancelled" : "unavailable"); }
        catch (Exception e) when (e is AccountBridgeHostException or BridgeStaleGenerationException or System.Text.Json.JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException)
        { return new(sent ? "unknown" : "rejected", "refreshRequired"); }
        finally { _write.Release(); }
    }
}
