using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

/// <summary>Availability must come from the current account's verified statistics, not UI input.</summary>
public sealed record GameplayHistoryEligibility(string State, DateTimeOffset? ImportedAt = null);

public sealed partial class GameplayTimeRuntime
{
    private readonly Func<string?> _verifiedHandle;
    private readonly Func<BridgeAccountContext, CancellationToken, Task<GameplayHistoryEligibility>>? _historyEligibility;
    private readonly SemaphoreSlim _historyGate = new(1, 1);
    private HistoryTicket? _historyTicket;
    private sealed record HistoryTicket(string Id, BridgeAccountContext Owner, long Generation,
        string Handle, DateTimeOffset ExpiresAt, GameplayHistoryPreview Preview);

    public async Task<BridgeDispatchBatch> DispatchHistoryAsync(BridgeEnvelope request, CancellationToken cancellation = default)
    {
        var entered = false;
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _current();
            if (request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                return HistoryResponse(request, "accountChanged");
            var body = request.Payload;
            Profiles.LocalPersonalProfileStore.RejectDuplicates(body);
            var field = request.Name switch {
                "gameplayTime.historyStatus" => "",
                "gameplayTime.historyPreview" => "path",
                "gameplayTime.historyConfirm" => "previewId",
                _ => throw new GameplayTimeException("gameplay.invalid_request")
            };
            if (body.GetRawText().Length > 8192 || body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.EnumerateObject().Any(p => p.Name != "schemaVersion" && p.Name != field))
                return Error(request, "gameplay.invalid_request");
            var argument = field.Length == 0 ? null : body.GetProperty(field).GetString();
            if (field.Length > 0 && (string.IsNullOrWhiteSpace(argument) || argument.Length > 4096))
                return Error(request, "gameplay.invalid_request");
            entered = await _historyGate.WaitAsync(0, cancellation);
            if (!entered) return HistoryResponse(request, "busy");
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            budget.CancelAfter(TimeSpan.FromSeconds(60));
            var token = budget.Token;
            bool Current() => !_disposed && !token.IsCancellationRequested && _current() == owner;
            Entry entry;
            lock (_sync)
            {
                if (!Current()) return HistoryResponse(request, "accountChanged");
                entry = Resolve()!;
                if (entry.Saved is null || entry.Error is not null) return HistoryResponse(request, "unavailable");
                if (entry.Saved.PendingReset is not null || entry.Saved.PendingImport is not null)
                    return HistoryResponse(request, "busy");
                if (entry.Saved.HistoryImportedAt is not null || entry.Saved.HistoryConsumed == true)
                    return HistoryResponse(request, "imported");
            }
            var handle = _verifiedHandle();
            if (string.IsNullOrWhiteSpace(handle)) return HistoryResponse(request, "identityRequired");
            var eligibility = _historyEligibility is null ? new GameplayHistoryEligibility("unavailable") :
                await _historyEligibility(owner.Context, token).ConfigureAwait(false);
            if (field == "previewId" && _historyRemote is not null && eligibility.State == "available")
                return HistoryResponse(request, await ConfirmRemoteHistoryAsync(owner.Context, owner.Generation,
                    argument!, handle, token).ConfigureAwait(false));
            lock (_sync)
            {
                if (!Current() || !string.Equals(handle, _verifiedHandle(), StringComparison.OrdinalIgnoreCase))
                    return HistoryResponse(request, "accountChanged");
                if (eligibility.State == "imported")
                {
                    // Persist a consumed marker, not another copy of the migrated duration.
                    // A later migration cannot reset a locally consumed opportunity either.
                    var saved = entry.Saved!;
                    entry.Saved = entry.Lease!.Save(saved, saved with {
                        HistoryImportedAt = eligibility.ImportedAt, HistoryConsumed = true }, Current);
                    _historyTicket = null;
                    return HistoryResponse(request, entry.HistoryState = "imported");
                }
                if (eligibility.State != "available")
                    return HistoryResponse(request, entry.HistoryState = "unavailable");
                entry.HistoryState = "available";
                if (field.Length == 0) return HistoryResponse(request, "available");
                if (entry.Desired != GameplayRecordingConsent.Allowed)
                    return HistoryResponse(request, "recordingRequired");
                if (field == "previewId")
                {
                    var ticket = _historyTicket;
                    if (ticket is null || ticket.Id != argument || ticket.Owner != owner.Context ||
                        ticket.Generation != owner.Generation || ticket.Handle != handle || ticket.ExpiresAt <= _time.GetUtcNow())
                        return HistoryResponse(request, "previewExpired");
                    var saved = entry.Saved!;
                    var total = checked(entry.Accumulator.PlayTimeSeconds + ticket.Preview.Seconds);
                    // Total and consumed marker share one atomic replace; failed writes consume nothing.
                    var next = saved with { Seconds = total, Consent = entry.Desired,
                        ShowOnProfile = entry.ShowOnProfile, FirstRecordedAt = entry.FirstRecordedAt,
                        HistoryImportedAt = _time.GetUtcNow(), HistoricalSeconds = ticket.Preview.Seconds,
                        ImportReceipt = ticket.Id, HistoryConsumed = true };
                    entry.Saved = entry.Lease!.Save(saved, next, Current);
                    entry.Accumulator.Restore(owner.Context, owner.Generation, entry.Desired, total);
                    entry.HistoryState = "imported";
                    _historyTicket = null;
                    return HistoryResponse(request, "imported");
                }
            }
            DateTimeOffset cutoff;
            lock (_sync)
            {
                if (!Current()) return HistoryResponse(request, "accountChanged");
                if (entry.FirstRecordedAt is null && entry.Accumulator.PlayTimeSeconds > 0)
                    return HistoryResponse(request, "overlapUnknown");
                cutoff = entry.FirstRecordedAt ?? _time.GetUtcNow();
                _historyTicket = null;
            }
            var preview = await Task.Run(() => GameplayHistoryScanner.Scan(argument!, handle, cutoff, token), token)
                .ConfigureAwait(false);
            lock (_sync)
            {
                if (!Current() || !string.Equals(handle, _verifiedHandle(), StringComparison.OrdinalIgnoreCase))
                    return HistoryResponse(request, "accountChanged");
                var id = Guid.NewGuid().ToString("N");
                _historyTicket = new(id, owner.Context, owner.Generation, handle, _time.GetUtcNow().AddMinutes(5), preview);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state = "preview",
                    previewId = id, seconds = preview.Seconds, sessions = preview.Sessions,
                    incompleteSessions = preview.IncompleteSessions, skippedFiles = preview.SkippedFiles }), []);
            }
        }
        catch (OperationCanceledException) { return HistoryResponse(request, "cancelled"); }
        catch (GameplayTimeException e) { return HistoryResponse(request, e.Code switch {
            "gameplay.history_path" => "path", "gameplay.history_empty" => "empty",
            "gameplay.history_limit" => "limit", "gameplay.account_changed" => "accountChanged", _ => "unavailable" }); }
        catch (Exception) { return HistoryResponse(request, "unavailable"); }
        finally { if (entered) _historyGate.Release(); }
    }

    private static BridgeDispatchBatch HistoryResponse(BridgeEnvelope request, string state) =>
        new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state }), []);
}
