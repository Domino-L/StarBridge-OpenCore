using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

internal sealed class CommunitySharingDispatcher(
    Func<(BridgeAccountContext? Context, long Generation)> current,
    Func<BridgeAccountContext, long, CancellationToken, Task<CommunitySharingTargets>> read,
    Func<BridgeAccountContext, long, CommunityMemberDirectoryRequest, CancellationToken, Task<CommunityMemberDirectoryPage>>? readMembers = null)
{
    internal Action<string, string, int?, long>? Diagnostic { get; set; }
    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = current();
            if (request.MessageType != BridgeMessageTypes.Request || request.Name is not ("privacy.communityTargets" or "privacy.communityMembers") ||
                owner.Context is null || request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                return Error("privacy_publication.account_changed");
            LocalPrivacyStore.RejectDuplicates(request.Payload);
            if (request.Name == "privacy.communityMembers")
            {
                if (readMembers is null) return Error("privacy_publication.member_scopes_unavailable");
                if (request.Payload.GetRawText().Length > 192 * 1024) return Error("privacy_publication.invalid_request");
                var input = request.Payload.Deserialize<CommunityMemberDirectoryRequest>(LocalPrivacyStore.Json);
                if (input is null) return Error("privacy_publication.invalid_request");
                PrivacyRelayWriter.ValidateMemberRequest(input);
                token.ThrowIfCancellationRequested();
                var page = await readMembers(owner.Context, owner.Generation, input, token).ConfigureAwait(false);
                if (owner != current() || token.IsCancellationRequested) return Error("privacy_publication.account_changed");
                return new(BridgeEnvelope.Response(request, page), []);
            }
            if (request.Payload.GetRawText().Length > 1024 || request.Payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                request.Payload.EnumerateObject().Any(p => p.Name != "schemaVersion")) return Error("privacy_publication.invalid_request");
            token.ThrowIfCancellationRequested();
            var result = await read(owner.Context, owner.Generation, token).ConfigureAwait(false);
            if (owner != current() || token.IsCancellationRequested) return Error("privacy_publication.account_changed");
            Record("ok");
            return new(BridgeEnvelope.Response(request, result), []);
        }
        catch (AccountBridgeHostException error) { return Error(error.Code); }
        catch (System.Net.Http.HttpRequestException)
        {
            return Error(request.Name == "privacy.communityMembers"
                ? "privacy_publication.member_scopes_unavailable"
                : "privacy_publication.community_scopes_unavailable");
        }
        catch (OperationCanceledException) { return Error("privacy_publication.account_changed"); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or
            FormatException or OverflowException or BridgeProtocolException or ArgumentException)
        { return Error("privacy_publication.invalid_request"); }
        BridgeDispatchBatch Error(string code)
        {
            Record(code);
            return new(BridgeEnvelope.ErrorResponse(request,
                new(code, "Organization sharing is unavailable.", true)), []);
        }
        void Record(string code)
        {
            if (request.Name != "privacy.communityTargets") return;
            try { Diagnostic?.Invoke("bridge", code, null, watch.ElapsedMilliseconds); }
            catch { /* Diagnostics must never change the request result. */ }
        }
    }
}
