using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<(object Data, ScmOAuthSession ActiveSession)> TradeProfileAsync(
        ScmOAuthSession session, bool write, JsonElement changes, Func<bool> current, CancellationToken token)
    {
        var needed = write ? new[] { "profile.read", "trade.read", "profile.write", "trade.write" } : new[] { "profile.read", "trade.read" };
        if (write && needed.Any(scope => !session.Capabilities.Contains(scope, StringComparer.Ordinal)))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var active = await EnsureActiveSessionAsync(session, token);
        if (active.Subject != session.Subject || active.AuthorityId != session.AuthorityId || !current())
            throw new AccountBridgeHostException("marketplace.context_changed");
        if (needed.Any(scope => !active.Capabilities.Contains(scope, StringComparer.Ordinal)))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        async Task<JsonElement> Send(HttpMethod method, object? body = null)
        {
            // Types and numeric SCM codes only: never log profile fields or server messages.
            var diagnosticId = ScmAuthDiagnostics.NewCorrelationId();
            var watch = ScmAuthDiagnostics.Start(diagnosticId, "trade-profile", $"method={method.Method}");
            try {
            token.ThrowIfCancellationRequested();
            if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
            using var request = new HttpRequestMessage(method, new Uri(options.ResourceServerBaseUri,
                "app-api/member/user/" + (method == HttpMethod.Get ? "get" : "update")));
            request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, diagnosticId);
            if (body is not null) request.Content = JsonContent.Create(body);
            try {
                using var response = await scmHttpClient.SendAsync(request, active.AccessToken, token);
                var envelope = await (method == HttpMethod.Get ? ReadMarketplaceEnvelopeAsync(response, "trade-profile", token)
                    : ReadMarketplaceWriteEnvelopeAsync(response, "trade-profile", token, (value, body) =>
                    {
                        var mapped = TradeProfileContract.Rejection(value,
                            body.TryGetProperty("msg", out var msg) && msg.ValueKind == JsonValueKind.String ? msg.GetString() : null);
                        return mapped == "trade_profile.rejected" ? null : mapped;
                    }));
                if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
                var code = envelope.GetProperty("code").GetInt64();
                ScmAuthDiagnostics.Write(diagnosticId, "trade-profile-envelope", "received",
                    $"method={method.Method} code={code.ToString(System.Globalization.CultureInfo.InvariantCulture)}");
                if (code != 0) throw new AccountBridgeHostException(TradeProfileContract.Rejection(code,
                    envelope.TryGetProperty("msg", out var message) ? message.GetString() : null));
                return envelope.GetProperty("data").Clone();
            } catch (ScmApiForbiddenException) { throw new AccountBridgeHostException("marketplace.forbidden"); }
            } catch (Exception exception) {
                ScmAuthDiagnostics.Failed(diagnosticId, "trade-profile", watch, exception,
                    exception is AccountBridgeHostException host ? $"code={host.Code}" : "");
                throw;
            }
        }
        var before = await Send(HttpMethod.Get);
        if (!write) {
            try {
                var projected = TradeProfileContract.Project(before);
                StartTradeWindowSync(active, before);
                return (projected, active);
            }
            catch (Exception exception) when (exception is not OperationCanceledException) {
                ScmAuthDiagnostics.Write("trade-profile", "trade-profile-projection", "failed", $"exceptionType={exception.GetType().Name}");
                throw;
            }
        }
        var merged = TradeProfileContract.Merge(before, changes);
        var uncertain = false;
        try { uncertain = (await Send(HttpMethod.Put, merged)).ValueKind != JsonValueKind.True; }
        catch (HttpRequestException e) when (e is ScmApiAuthenticationException || e.StatusCode == System.Net.HttpStatusCode.Unauthorized)
        { throw new AccountBridgeHostException("marketplace.sign_in_required"); }
        catch (Exception e) when (e is HttpRequestException or IOException or ScmApiUnavailableException or ScmApiProtocolException ||
            e is OperationCanceledException && !token.IsCancellationRequested)
        { uncertain = true; } // A client timeout is not a user cancel: the PUT may have landed.
        // Never replay PUT. A read-back is the only reconciliation operation.
        try {
            var actual = await Send(HttpMethod.Get);
            StartTradeWindowSync(active, actual);
            return (new { profile = TradeProfileContract.Project(actual), confirmed = !uncertain, requiresReview = uncertain }, active);
        } catch (AccountBridgeHostException) { throw; }
        catch (Exception e) when (e is not OperationCanceledException && current()) {
            throw new AccountBridgeHostException("trade_profile.unknown");
        }
    }
}
