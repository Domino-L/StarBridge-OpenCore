using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private BridgeEnvelope PrepareFriendsCommandPages(BridgeEnvelope request, BridgeEnvelope response,
        FriendsDisplayTransaction? transaction)
    {
        if (response.Status != BridgeResponseStatuses.Ok ||
            !response.Payload.TryGetProperty("status", out var status) || status.GetString() != "accepted") return response;
        JsonObject Header()
        {
            var body = new JsonObject();
            // Do not reparse/copy the entire large directory to replace it.
            foreach (var property in response.Payload.EnumerateObject())
                if (property.Name != "directory") body[property.Name] = JsonNode.Parse(property.Value.GetRawText());
            return body;
        }
        BridgeEnvelope UnavailableDirectory()
        {
            // The write is confirmed. Losing its presentation must neither
            // turn it into an uncertain outcome nor replay the operation.
            var body = Header();
            body["directoryState"] = "unavailable";
            body["directorySyncError"] = "refreshRequired";
            return response with { Payload = JsonSerializer.SerializeToElement(body, BridgeProtocol.JsonOptions) };
        }
        if (!FriendsReader.WantsPagedResponse(request.Payload))
            return JsonSerializer.SerializeToUtf8Bytes(response, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes
                ? response : UnavailableDirectory();
        if (transaction?.Current != true || response.AccountContext is not { } owner)
            return BridgeEnvelope.CancelledResponse(request);
        if (!response.Payload.TryGetProperty("directory", out var directory)) return UnavailableDirectory();
        var current = transaction.CaptureSnapshotCurrent(Volatile.Read(ref _friendPageRevision));
        try
        {
            var page = _friendPages.Open(directory, owner, request.SessionGeneration, "fresh", current);
            if (!current()) return BridgeEnvelope.CancelledResponse(request);
            var body = Header();
            body["directoryState"] = "paged";
            body["directory"] = JsonNode.Parse(page.GetRawText());
            var result = response with { Payload = JsonSerializer.SerializeToElement(body, BridgeProtocol.JsonOptions) };
            return JsonSerializer.SerializeToUtf8Bytes(result, BridgeProtocol.JsonOptions).Length <= BridgeProtocol.MaximumFrameBytes
                ? result : UnavailableDirectory();
        }
        catch (AccountBridgeHostException) { return UnavailableDirectory(); }
    }
}
