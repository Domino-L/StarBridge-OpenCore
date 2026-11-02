namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private async ValueTask<BridgeDispatchBatch> PreviewRallyAsync(BridgeEnvelope request, CancellationToken token)
    {
        BridgeDispatchBatch Reply(BridgeEnvelope response) => new(response, []);
        BridgeDispatchBatch Error(string code) => Reply(BridgeEnvelope.ErrorResponse(request,
            new BridgeError("notificationSettings." + code, "Rally preview unavailable.")));
        try
        {
            RallyBannerNotice notice;
            lock (_gate)
            {
                ObjectDisposedException.ThrowIf(_disposed, this);
                token.ThrowIfCancellationRequested();
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.SessionGeneration != generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                if (request.AccountContext != null || request.MessageType != BridgeMessageTypes.Request) throw new ArgumentException();
                try { Fields(request.Payload, "schemaVersion"); }
                catch (InvalidDataException) { return Error("invalid_request"); }
                if (request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
                var settings = Read();
                var started = _rallyTime.GetTimestamp();
                var id = Guid.NewGuid();
                bool Current()
                {
                    lock (_gate) return !_disposed && request.SessionGeneration == generation() && _sampleRallyId == id &&
                        _rallyTime.GetElapsedTime(started) < TimeSpan.FromSeconds(8);
                }
                notice = new(id, "", _rallyTime.GetUtcNow().AddMinutes(30), settings.Preview, Current) { Sample = true };
                ClearRallyBanner(ref _sampleRallyId);
                _sampleRallyId = id;
            }
            var sound = TryPlayRally(notice.IsCurrent);
            var banner = await PresentRallyAsync(notice, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            return Reply(BridgeEnvelope.Response(request, new { schemaVersion = 1, banner, sound }, preserveRequestAccountContext: false));
        }
        catch (OperationCanceledException) { return Reply(BridgeEnvelope.CancelledResponse(request)); }
        catch (BridgeProtocolException e) { return Reply(BridgeEnvelope.ErrorResponse(request, new BridgeError(e.Code, "Rally preview rejected."))); }
        catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or JsonException)
        { return Error("read_failed"); }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or OverflowException or FormatException or KeyNotFoundException)
        { return Error("invalid_request"); }
    }
}
