using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly FriendsDirectoryPageStore _friendPages = new();
    private long _friendPageRevision;
    private void InvalidateFriendsPages(long _) => RetireFriendsPages();
    private void RetireFriendsPages()
    {
        Interlocked.Increment(ref _friendPageRevision);
        _friendPages.Clear();
    }
    private BridgeEnvelope PrepareFriendsPageResponse(BridgeEnvelope request, BridgeEnvelope response,
        FriendsDisplayTransaction? transaction)
    {
        if (request.Name == AccountBridgeRequestNames.ExecuteFriend)
            return PrepareFriendsCommandPages(request, response, transaction);
        if (request.Name != AccountBridgeRequestNames.ReadFriends || response.Status != "ok" ||
            !FriendsReader.WantsPagedResponse(request.Payload)) return response;
        if (transaction?.Current != true || response.AccountContext is not { } owner)
            return BridgeEnvelope.CancelledResponse(request);
        var current = transaction.CaptureSnapshotCurrent();
        try
        {
            var payload = _friendPages.Open(response.Payload, owner, request.SessionGeneration, "fresh", current);
            return current() ? response with { Payload = payload } : BridgeEnvelope.CancelledResponse(request);
        }
        catch (AccountBridgeHostException error)
        { return BridgeEnvelope.ErrorResponse(request, new(error.Code, "Directory snapshot is unavailable. Refresh and try again.", error.Retryable)); }
    }

    private BridgeDispatchBatch ReadFriendsPage(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            BridgeEnvelopeValidator.RequireAccountContext(request.Name, request.AccountContext);
            token.ThrowIfCancellationRequested();
            var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (request.MessageType != "request" || fields.Distinct().Count() != fields.Length ||
                fields.Any(name => name is not ("schemaVersion" or "snapshotId" or "offset" or "displayRequestId")) ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                request.Payload.GetProperty("snapshotId").GetString() is not { } id || !Guid.TryParseExact(id, "N", out _))
                throw new AccountBridgeHostException("friends.invalid_request");
            if (request.SessionGeneration != Generation) throw new BridgeStaleGenerationException(request.SessionGeneration, Generation);
            if (_host is not ScmAccountBridgeHost scm) throw new AccountBridgeHostException("friends.read_unavailable");
            scm.RequireFriendsPageContext(request.AccountContext!);
            var partition = "fresh";
            if (request.Payload.TryGetProperty("displayRequestId", out var origin))
            {
                if (origin.GetString() is not { Length: > 0 and <= 1024 } displayRequestId)
                    throw new AccountBridgeHostException("friends.invalid_request");
                partition = "display:" + displayRequestId;
            }
            // This projection never refreshes credentials or mutates identity.
            // Keeping it outside the account IO lane also lets pending directory
            // reads consume their own cached pages without taking another slot.
            var payload = _friendPages.Read(id, request.Payload.GetProperty("offset").GetInt32(), request.AccountContext!, request.SessionGeneration, partition);
            // A concurrent credential failure may leave generation unchanged.
            // Recheck the actual session after materializing the bounded page.
            scm.RequireFriendsPageContext(request.AccountContext!);
            token.ThrowIfCancellationRequested();
            return new(BridgeEnvelope.Response(request, payload), []);
        }
        catch (AccountBridgeHostException error)
        { return new(BridgeEnvelope.ErrorResponse(request, new(error.Code, "Directory snapshot is unavailable. Refresh and try again.", error.Retryable)), []); }
        catch (BridgeProtocolException error)
        { return new(BridgeEnvelope.ErrorResponse(request, new(error.Code, "Directory snapshot scope has changed.")), []); }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException or ArgumentException)
        { return new(BridgeEnvelope.ErrorResponse(request, new("friends.invalid_request", "Invalid directory page request.")), []); }
    }
}
