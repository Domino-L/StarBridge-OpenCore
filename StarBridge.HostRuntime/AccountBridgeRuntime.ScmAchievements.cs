using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private sealed record ScmCatalogPage(BridgeAccountContext Owner, long Generation, DateTimeOffset At, Achievements.ScmAchievementCatalog Catalog);
    private ScmCatalogPage? _scmCatalogPage;
    private async ValueTask<BridgeDispatchBatch> ReadScmAchievementsAsync(BridgeEnvelope request, CancellationToken token)
    {
        BridgeDispatchBatch Error(string code, bool retryable = false) => new(BridgeEnvelope.ErrorResponse(request,
            new(code, "SCM achievement collection is unavailable.", retryable)), []);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _host.CurrentContext; var generation = Generation;
            if (_disposed || request.MessageType != BridgeMessageTypes.Request || owner is null || request.AccountContext != owner || request.SessionGeneration != generation)
                return Error("scmAchievements.account_changed");
            Profiles.LocalPersonalProfileStore.RejectDuplicates(request.Payload);
            if (request.Payload.ValueKind != JsonValueKind.Object || request.Payload.GetRawText().Length > 256 ||
                request.Payload.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "offset" or "snapshotId")) ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                return Error("scmAchievements.invalid_request");
            bool Current() => !_disposed && !token.IsCancellationRequested && Generation == generation && _host.CurrentContext == owner;
            var offset = request.Payload.TryGetProperty("offset", out var position) ? position.GetInt32() : 0;
            var snapshotId = request.Payload.TryGetProperty("snapshotId", out var supplied) ? supplied.GetString() : null;
            Achievements.ScmAchievementCatalog catalog;
            if (snapshotId is null && offset == 0) {
                catalog = await _host.ReadScmAchievementsAsync(owner, token).ConfigureAwait(false);
                if (!Current()) return Error("scmAchievements.account_changed");
                catalog.Validate();
                try { if (_scmAchievementUnlocks is { } unlocks) await unlocks.ObserveAsync(owner, generation, catalog).ConfigureAwait(false); }
                catch (Exception failure) when (failure is IOException or UnauthorizedAccessException or JsonException or OperationCanceledException) { }
                _scmAchievementUnlocks?.Wake();
                Volatile.Write(ref _scmCatalogPage, new(owner, generation, DateTimeOffset.UtcNow, catalog));
                try { _offlineAccount?.ObserveScmAchievements(owner, catalog, Current); }
                catch (Exception failure) when (failure is IOException or UnauthorizedAccessException or InvalidOperationException) { }
            } else {
                var page = Volatile.Read(ref _scmCatalogPage);
                if (page is null || page.Owner != owner || page.Generation != generation ||
                    page.At < DateTimeOffset.UtcNow.AddMinutes(-5)) return Error("scmAchievements.snapshot_changed", true);
                catalog = page.Catalog;
            }
            token.ThrowIfCancellationRequested();
            if (!Current()) return Error("scmAchievements.account_changed");
            var payload = Achievements.ScmAchievementPages.Read(catalog, offset, snapshotId, false);
            return Current() ? new(BridgeEnvelope.Response(request, payload), []) : Error("scmAchievements.account_changed");
        }
        catch (Auth.ScmApiAuthenticationException) { return Error("scmAchievements.not_allowed"); }
        catch (Auth.ScmApiForbiddenException) { return Error("scmAchievements.not_allowed"); }
        catch (Auth.ScmApiProtocolException) { return Error("scmAchievements.invalid_response"); }
        catch (Auth.ScmApiUnavailableException) { return Error("scmAchievements.unavailable", true); }
        catch (AccountBridgeHostException failure) { return Error(failure.Code); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (HttpRequestException) { return Error("scmAchievements.unavailable", true); }
        catch (Exception failure) when (failure is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException or
            OverflowException or FormatException or BridgeProtocolException or InvalidDataException)
        { return Error("scmAchievements.invalid_response"); }
    }
}
