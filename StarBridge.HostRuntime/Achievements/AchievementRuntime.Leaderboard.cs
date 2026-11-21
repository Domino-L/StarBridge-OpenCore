using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

internal sealed partial class AchievementRuntime
{
    private readonly SemaphoreSlim _leaderboardGate = new(1);
    private (BridgeAccountContext? Context, long Generation) _leaderboardOwner;
    private LeaderboardConsent? _leaderboardConsent;
    private DateTimeOffset _consentAt, _leaderboardRetryAt;
    private bool _leaderboardUnsupported;

    private async Task<BridgeDispatchBatch> DispatchLeaderboardAsync(BridgeEnvelope request,
        (BridgeAccountContext? Context, long Generation) owner, CancellationToken token)
    {
        var write = request.Name == "achievements.leaderboard.consent.write";
        var board = request.Name == "achievements.leaderboard.read";
        if (request.MessageType != BridgeMessageTypes.Request ||
            !write && !board && request.Name != "achievements.leaderboard.consent.read" ||
            request.Payload.GetRawText().Length > 128 || request.Payload.EnumerateObject().Count() != (write ? 2 : 1) ||
            request.Payload.GetProperty("schemaVersion").GetInt32() != 1 ||
            write && (!request.Payload.TryGetProperty("optIn", out var choice) || choice.ValueKind is not (JsonValueKind.True or JsonValueKind.False)))
            return Error(request, "achievements.invalid_request");
        using var work = _retirement.Enter(token);
        if (work is null) return Error(request, "achievements.unavailable");
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(work.Token);
        budget.CancelAfter(TimeSpan.FromSeconds(8));
        token = budget.Token;
        await _leaderboardGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            bool Current() => !_disposed && !token.IsCancellationRequested && _current() == owner;
            if (!Current()) return Error(request, "achievements.account_changed");
            if (_leaderboardOwner != owner)
            {
                _leaderboardOwner = owner; _leaderboardConsent = null;
                _consentAt = _leaderboardRetryAt = default; _leaderboardUnsupported = false;
            }
            TsgSwiftLeaderboard? leaderboard = null;
            var now = _time.GetUtcNow();
            if (_leaderboardUnsupported && now < _leaderboardRetryAt)
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, supported = false }), []);
            // Withdrawal must remain possible even during opt-in/read throttling.
            if (now < _leaderboardRetryAt && !(write && !request.Payload.GetProperty("optIn").GetBoolean()))
                return Error(request, "achievements.leaderboard.rate_limited");
            if (write)
            {
                var consent = await _remote.WriteLeaderboardConsentAsync(owner.Context!, owner.Generation,
                    request.Payload.GetProperty("optIn").GetBoolean(), token).ConfigureAwait(false);
                consent.Validate();
                if (!Current()) return Error(request, "achievements.account_changed");
                _leaderboardConsent = consent; _consentAt = now;
                _changed(owner.Generation);
            }
            else if (board)
            {
                var value = await _remote.ReadLeaderboardAsync(owner.Context!, owner.Generation, token).ConfigureAwait(false);
                value.Validate();
                if (!Current()) return Error(request, "achievements.account_changed");
                leaderboard = value;
            }
            else if (!board && (_leaderboardConsent is null || now - _consentAt >= TimeSpan.FromSeconds(60)))
            {
                var value = await _remote.ReadLeaderboardConsentAsync(owner.Context!, owner.Generation, token).ConfigureAwait(false);
                value.Validate();
                if (!Current()) return Error(request, "achievements.account_changed");
                _leaderboardConsent = value; _consentAt = now;
            }
            if (!Current()) return Error(request, "achievements.account_changed");
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, supported = true,
                board = board ? leaderboard : null, consent = board ? null : _leaderboardConsent }), []);
        }
        catch (HttpRequestException e) when (e.StatusCode == HttpStatusCode.NotFound)
        {
            if (_current() != owner) return Error(request, "achievements.account_changed");
            _leaderboardUnsupported = true; _leaderboardRetryAt = _time.GetUtcNow().AddHours(1);
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, supported = false }), []);
        }
        catch (ScmApiRateLimitException e)
        {
            if (_current() == owner) _leaderboardRetryAt = _time.GetUtcNow().Add(e.RetryAfter is { } delay && delay >= TimeSpan.FromSeconds(60) && delay <= TimeSpan.FromHours(1) ? delay : TimeSpan.FromSeconds(60));
            return Error(request, "achievements.leaderboard.rate_limited");
        }
        catch (Exception e) when (e is not OutOfMemoryException)
        { return Error(request, "achievements.leaderboard.unavailable"); }
        finally { _leaderboardGate.Release(); }
    }
}