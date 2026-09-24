using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameplayTimeRuntime
{
    private sealed record ResetTicket(string Id, BridgeAccountContext Owner, long Generation, long Revision, DateTimeOffset Expires);
    private ResetTicket? _resetTicket;

    public async Task<BridgeDispatchBatch> DispatchResetAsync(BridgeEnvelope request, IGameplayTimeResetRemote remote,
        CancellationToken cancellation = default)
    {
        BridgeDispatchBatch Reply(string state, string? previewId = null) =>
            new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state, previewId }), []);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _current();
            bool Current() => !_disposed && !cancellation.IsCancellationRequested && _current() == owner;
            if (request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation || !Current())
                return Reply("accountChanged");
            var body = request.Payload;
            Profiles.LocalPersonalProfileStore.RejectDuplicates(body);
            var confirm = request.Name == "gameplayTime.resetConfirm";
            if (request.Name is not ("gameplayTime.resetPreview" or "gameplayTime.resetConfirm" or "gameplayTime.resetStatus") ||
                body.GetRawText().Length > 1024 || body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.EnumerateObject().Any(p => p.Name != "schemaVersion" && !(confirm && p.Name == "previewId")))
                return Error(request, "gameplay.invalid_request");
            if (request.Name == "gameplayTime.resetStatus")
            {
                await ResetAsync(owner.Context, owner.Generation, null, remote, cancellation).ConfigureAwait(false);
                lock (_sync)
                {
                    if (!Current()) return Reply("accountChanged");
                    var entry = Resolve();
                    return Reply(entry?.Saved is null ? "unavailable" : entry.Saved.PendingReset is null ? "idle" : "pending");
                }
            }
            if (confirm)
            {
                ResetTicket? ticket;
                lock (_sync)
                {
                    ticket = _resetTicket;
                    if (!Current() || ticket is null || ticket.Owner != owner.Context || ticket.Generation != owner.Generation ||
                        ticket.Id != body.GetProperty("previewId").GetString() || ticket.Expires <= _time.GetUtcNow())
                        return Reply("previewExpired");
                    _resetTicket = null; // Consume before awaiting. No duplicate confirmation can submit a new reset.
                }
                return Reply(await ResetAsync(owner.Context, owner.Generation, ticket.Revision, remote, cancellation).ConfigureAwait(false));
            }
            lock (_sync)
            {
                if (!Current()) return Reply("accountChanged");
                _resetTicket = null;
                var entry = Resolve();
                if (entry?.Saved is null || entry.Error is not null) return Reply("unavailable");
                if (entry.Saved.PendingReset is not null) return Reply("pending");
            }
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            budget.CancelAfter(TimeSpan.FromSeconds(15));
            var state = await remote.ReadAsync(owner.Context, budget.Token).ConfigureAwait(false);
            lock (_sync)
            {
                if (!Current()) return Reply("accountChanged");
                if (state.SchemaVersion != 1 || state.Revision < 0) return Reply("unavailable");
                _resetTicket = new(Guid.NewGuid().ToString("N"), owner.Context, owner.Generation, state.Revision,
                    _time.GetUtcNow().AddMinutes(5));
                return Reply("ready", _resetTicket.Id);
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException) { return Reply("unavailable"); }
    }
}
