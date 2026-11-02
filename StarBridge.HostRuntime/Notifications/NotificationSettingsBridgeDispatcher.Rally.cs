namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private readonly Dictionary<string, bool> _rallyEligibility = new(StringComparer.Ordinal);
    private readonly HashSet<string> _seenRallies = new(StringComparer.Ordinal);
    private string? _currentRallyId;
    private long _rallyEpoch;
    private Guid? _bannerRallyId;
    private Guid? _sampleRallyId;

    private void ClearRallyBanner(ref Guid? id)
    {
        var previous = id;
        id = null;
        if (previous is { } value)
        {
            try { rallyBanner?.Clear(value); }
            catch (Exception) { /* Native cleanup cannot change the domain response. */ }
        }
    }

    private void InvalidateRally()
    {
        ClearRallyHotkeys();
        _currentRallyId = null;
        ClearRallyBanner(ref _bannerRallyId);
    }

    private void ResetRallies()
    {
        _rallyEligibility.Clear();
        _seenRallies.Clear();
        InvalidateRally();
        ClearRallyBanner(ref _sampleRallyId);
        _rallyEpoch++;
    }

    private async ValueTask<BridgeEnvelope> ObserveRallyAsync(
        BridgeEnvelope request, BridgeEnvelope response, CancellationToken token)
    {
        RallyBannerNotice? notice = null;
        lock (_gate)
        {
            if (_disposed || token.IsCancellationRequested || request.SessionGeneration != generation() ||
                response.Status != BridgeResponseStatuses.Ok) return response;
            try
            {
                var action = request.Payload.GetProperty("action").GetString();
                var source = request.Payload.GetProperty("sourceRef").GetString()!;
                var settings = Read();
                if (!settings.RallyAlertsEnabled) InvalidateRally();
                if (action == "eligibility")
                {
                    _rallyEligibility[source] = response.Payload.GetProperty("canStart").GetBoolean();
                    return response;
                }
                if (action is not ("read" or "respond" or "end")) return response;
                var rally = response.Payload.GetProperty("rally");
                var id = rally.ValueKind == JsonValueKind.Null ? null : rally.GetProperty("rallyId").GetString();
                if (action is "respond" or "end")
                {
                    if (id is null || id == _currentRallyId) InvalidateRally();
                    return response;
                }
                var active = id != null && rally.GetProperty("state").GetString() == "active" &&
                    rally.GetProperty("response").ValueKind == JsonValueKind.Null;
                if (id != _currentRallyId || !active) InvalidateRally();
                if (!active) return response;
                if (rally.GetProperty("expiresAt").GetDateTimeOffset() <= _rallyTime.GetUtcNow())
                { InvalidateRally(); return response; }
                if (!_rallyEligibility.TryGetValue(source, out var canStart) || canStart) return response;
                if (!request.Payload.GetProperty("online").GetBoolean()) InvalidateRally();
                if (!_seenRallies.Add(id!)) return response;
                if (_seenRallies.Count > 256) _seenRallies.Clear();
                // Consume before offline, settings and native admission gates: never replay.
                if (!request.Payload.GetProperty("online").GetBoolean()) { InvalidateRally(); return response; }
                if (!settings.RallyAlertsEnabled) return response;
                var expiresAt = rally.GetProperty("expiresAt").GetDateTimeOffset();
                var text = rally.GetProperty("text").GetString()!;
                _currentRallyId = id;
                var epoch = ++_rallyEpoch;
                bool Current()
                {
                    lock (_gate) return !_disposed && request.SessionGeneration == generation() &&
                        _rallyTime.GetUtcNow() < expiresAt && _currentRallyId == id && _rallyEpoch == epoch;
                }
                notice = new(Guid.NewGuid(), text, expiresAt, settings.Preview, Current);
                RegisterRallyHotkeys(id!, request.SessionGeneration, expiresAt, Current);
                if (rallyBanner != null) _bannerRallyId = notice.Id;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or
                InvalidOperationException or KeyNotFoundException or FormatException or Settings.ApplicationPreferencesException)
            { return response; }
        }
        TryPlayRally(notice.IsCurrent);
        await PresentRallyAsync(notice, token).ConfigureAwait(false);
        return response;
    }

    private bool TryPlayRally(Func<bool> current)
    {
        try { return current() && playRally?.Invoke(current) == true; }
        catch (Exception) { return false; }
    }

    private async ValueTask<bool> PresentRallyAsync(RallyBannerNotice notice, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(1));
        try
        {
            if (token.IsCancellationRequested || !notice.IsCurrent()) return false;
            if (rallyBanner != null)
                return await rallyBanner.TryPresentAsync(notice, deadline.Token).AsTask().WaitAsync(deadline.Token).ConfigureAwait(false);
            if (overlay != null)
                return await overlay.TryPresentAsync(new(notice.Id, 0, 0, notice.Preview, notice.IsCurrent)
                    { Rally = new(notice.Text, notice.ExpiresAt, notice.Sample) }, deadline.Token).AsTask().WaitAsync(deadline.Token).ConfigureAwait(false);
        }
        catch (Exception) { /* An uncertain submission is consumed; never retry. */ }
        finally
        {
            if (rallyBanner != null && !notice.IsCurrent())
            {
                try { rallyBanner.Clear(notice.Id); }
                catch (Exception) { }
            }
        }
        return false;
    }
}
