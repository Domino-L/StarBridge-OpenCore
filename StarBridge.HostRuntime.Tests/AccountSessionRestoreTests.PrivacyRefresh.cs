using System.Net;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task PrivacyRefresh(string? onlyOutcome = null)
    {
        foreach (var outcome in new[] { "success", "repeated401", "refreshFailure", "refresh408", "refresh429",
            "refreshNetwork", "refreshTimeout", "refreshIdentity503", "invalidGrant", "refresh401", "closeDuringReplay",
            "refresh401Empty", "refresh401Html", "refresh401InvalidJson", "refresh401InvalidClient",
            "invalidGrant401", "refresh400Html", "refresh2xxInvalidJson" })
        {
            if (onlyOutcome is not null && onlyOutcome != outcome) continue;
            var root = Directory.CreateTempSubdirectory("sharing-refresh-").FullName;
            try
            {
                var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
                var vault = new MemoryTokenVault();
                vault.SaveRefreshToken($"{options.AuthorityId}:subject-1", "synthetic-refresh");
                var refreshes = 0;
                var recovered = false;
                var rejected = outcome is "invalidGrant" or "invalidGrant401";
                var transient = outcome == "repeated401" || outcome.StartsWith("refresh", StringComparison.Ordinal) && !rejected;
                using var authHandler = new ScriptedHandler(request => {
                    if (request.RequestUri != options.TokenEndpoint)
                    {
                        if (refreshes > 1 && !recovered && outcome == "refreshIdentity503")
                            return JsonResponse(HttpStatusCode.ServiceUnavailable, "{}");
                        return JsonResponse(HttpStatusCode.OK,
                            "{\"subject\":\"subject-1\",\"displayName\":\"Synthetic Pilot\",\"capabilities\":[\"profile.read\"]}");
                    }
                    refreshes++;
                    if (refreshes > 1 && !recovered)
                    {
                        if (outcome == "refreshNetwork") throw new HttpRequestException("Synthetic connection/DNS failure");
                        if (outcome == "refreshTimeout") throw new TaskCanceledException();
                        if (outcome == "invalidGrant") return JsonResponse(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}");
                        if (outcome == "invalidGrant401") return JsonResponse(HttpStatusCode.Unauthorized, "{\"error\":\"invalid_grant\"}");
                        if (outcome == "refresh401") return JsonResponse(HttpStatusCode.Unauthorized, "{}");
                        if (outcome == "refresh401Empty") return JsonResponse(HttpStatusCode.Unauthorized, "");
                        if (outcome == "refresh401Html") return new(HttpStatusCode.Unauthorized) {
                            Content = new StringContent("<html>Unauthorized</html>", System.Text.Encoding.UTF8, "text/html") };
                        if (outcome == "refresh401InvalidJson") return JsonResponse(HttpStatusCode.Unauthorized, "{");
                        if (outcome == "refresh401InvalidClient") return JsonResponse(HttpStatusCode.Unauthorized, "{\"error\":\"invalid_client\"}");
                        if (outcome == "refresh400Html") return JsonResponse(HttpStatusCode.BadRequest, "<html>Bad Request</html>");
                        if (outcome == "refresh2xxInvalidJson") return JsonResponse(HttpStatusCode.OK, "{");
                        if (transient && outcome is not ("refreshIdentity503" or "repeated401")) return JsonResponse(outcome switch {
                            "refresh408" => HttpStatusCode.RequestTimeout, "refresh429" => HttpStatusCode.TooManyRequests,
                            _ => HttpStatusCode.ServiceUnavailable }, "{}");
                    }
                    return JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access-" + refreshes +
                        "\",\"refresh_token\":\"synthetic-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
                });
                var oauth = new OAuthPkceClient(new ScmHttpClient(authHandler), vault, options);
                var session = (await oauth.TryRestoreSessionAsync(default))!;
                var writes = 0;
                var clears = 0;
                var replayAdmitted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                using var releaseReplay = new ManualResetEventSlim();
                var replayInFlight = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                using var releaseResponse = new ManualResetEventSlim();
                using var relay = new ScriptedHandler(request => {
                    if (request.Method == HttpMethod.Get)
                        return JsonResponse(HttpStatusCode.OK, "{\"fleetCode\":null}");
                    var body = request.Content!.ReadAsStringAsync().GetAwaiter().GetResult();
                    using var json = System.Text.Json.JsonDocument.Parse(body);
                    if (json.RootElement.GetProperty("online").GetBoolean())
                    {
                        writes++;
                        if (writes == 1 || outcome == "repeated401" && !recovered) return new(HttpStatusCode.Unauthorized);
                        if (outcome == "closeDuringReplay")
                        { replayInFlight.TrySetResult(); releaseResponse.Wait(TimeSpan.FromSeconds(4)); }
                    }
                    else clears++;
                    var response = JsonResponse(HttpStatusCode.OK, body);
                    response.Headers.Add("X-StarBridge-Realtime-Version", "1");
                    return response;
                });
                using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), relay);
                var owner = new BridgeAccountContext("test", "sharing.invalid", "fixture");
                PrivacyPublicationInput? input = new(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
                var store = new LocalPrivacyStore(root);
                var clock = new SharingTestClock();
                store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                    new(PlayerSharedStateFields.Presence, false, true, []), new(PlayerSharedStateFields.None, false)), () => true);
                using var publication = new PrivacyPublication(store, () => input, async (current, body, ct) => {
                    var result = await PrivacyPublicationAuthentication.SendAsync(oauth, session, async (active, token) => {
                        session = active; // Match the Host's pre-send session adoption.
                        await writer.SendAsync(active.AccessToken, body, token, () => {
                            current.RequirePositiveAdmission?.Invoke();
                            if (outcome == "closeDuringReplay" && writes == 1 && body.GetProperty("online").GetBoolean())
                            { replayAdmitted.TrySetResult(); releaseReplay.Wait(token); }
                        }, admission: current.PositiveAdmission);
                        return true;
                    }, ct);
                    session = result.ActiveSession;
                }, startTimer: false, timeProvider: clock);
                oauth.SessionInvalidated += (_, _) => { input = null; publication.Invalidate(); };
                if (outcome == "closeDuringReplay")
                {
                    var sending = Task.Run(() => publication.ApplyAsync(owner, 1, 1, default));
                    await replayAdmitted.Task.WaitAsync(TimeSpan.FromSeconds(3));
                    var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                    var closing = Task.Run(async () => {
                        started.TrySetResult();
                        store.Save(owner, 1, Guid.NewGuid().ToString("N"), store.Read(owner).Settings! with {
                            PublicationEnabled = false }, () => true);
                        await publication.StopAsync(default, explicitRequest: true);
                    });
                    bool beforeSend, duringSend;
                    try
                    {
                        await started.Task;
                        beforeSend = await Task.WhenAny(closing, Task.Delay(80)) != closing;
                        releaseReplay.Set();
                        await replayInFlight.Task.WaitAsync(TimeSpan.FromSeconds(3));
                        duringSend = await Task.WhenAny(closing, Task.Delay(80)) != closing;
                    }
                    finally { releaseReplay.Set(); releaseResponse.Set(); }
                    await Task.WhenAll(sending, closing).WaitAsync(TimeSpan.FromSeconds(4));
                    AssertEqual(true, beforeSend && duringSend, "close waits across OAuth replay admission and HTTP");
                    AssertEqual(true, clears > 0, "OAuth replay close immediately clears");
                    await publication.TickAsync(); publication.Invalidate(); await publication.TickAsync();
                    AssertEqual(2, writes, "no positive replay after close returns");
                    Console.WriteLine("PASS M04c OAuth replay admission and close");
                    continue;
                }
                await publication.ApplyAsync(owner, 1, 1, default);
                AssertEqual(outcome == "success" ? "applied" : transient ? "reconnecting" : "identityRequired", publication.Status.State,
                    "actual OAuth refresh and writer result: " + outcome);
                AssertEqual(true, store.HasPublicationConsent(owner), "refresh cannot revoke sharing consent");
                if (rejected)
                    AssertEqual("privacy_publication.identity_unavailable", publication.Status.ErrorCode,
                        "exhausted refresh must require sign-in");
                AssertEqual(outcome == "repeated401" ? 2 : transient || rejected ? 1 : 2, writes, "one replay at most");
                // Initial restore plus one existing refresh, with no automatic login.
                // Compensating withdrawal may consult that same existing session.
                AssertEqual(true, refreshes >= 2, "401 reached the existing refresh mechanism");
                if (rejected)
                {
                    AssertEqual<string?>(null, vault.LoadRefreshToken($"{options.AuthorityId}:subject-1"),
                        "explicit rejection retires the vault credential");
                    var before = refreshes;
                    recovered = true;
                    foreach (var seconds in new[] { 60, 300, 900, 900 }) {
                        clock.Advance(seconds); await publication.TickAsync(); await publication.TickAsync();
                    }
                    AssertEqual(before, refreshes, "rejected refresh must not retry after input wakes or deadlines");
                    AssertEqual(1, writes, "rejected refresh cannot resume positive publication");
                    AssertEqual("identityRequired", publication.Status.State, "rejected refresh stays sign-in required");
                }
                if (transient)
                {
                    AssertEqual("synthetic-next", vault.LoadRefreshToken($"{options.AuthorityId}:subject-1"),
                        "temporary refresh retains the vault credential");
                    AssertEqual(true, outcome == "refresh2xxInvalidJson"
                        ? publication.Status.ErrorCode == "privacy_publication.response_invalid"
                        : publication.Status.ErrorCode is "privacy_publication.temporarily_unavailable" or
                        "privacy_publication.rejected" or "privacy_publication.network_unavailable" or
                        "privacy_publication.timeout" or "privacy_publication.server_error" or "privacy_publication.rate_limited",
                        "refresh transport failure must explain network problem");
                    if (outcome.StartsWith("refresh401", StringComparison.Ordinal))
                    {
                        // Exercise repeated outages beyond the raw-resource-401 identity threshold.
                        // An uncertain initial publish owes a clear before positive recovery.
                        // Failed clears use the existing 1/5/15 minute backoff (15 minute cap).
                        foreach (var seconds in new[] { 60, 300, 900, 900 })
                        {
                            var before = refreshes;
                            await publication.TickAsync(); await publication.TickAsync();
                            AssertEqual(before, refreshes, "input wakes cannot bypass refresh backoff");
                            clock.Advance(seconds - 1);
                            await publication.TickAsync();
                            AssertEqual(before, refreshes, "refresh cannot retry before deadline");
                            clock.Advance(1);
                            await publication.TickAsync();
                            AssertEqual(before + 1, refreshes, "one refresh at the existing clear deadline");
                            AssertEqual("reconnecting", publication.Status.State, "repeated transient 401 stays recoverable");
                            AssertEqual("synthetic-next", vault.LoadRefreshToken($"{options.AuthorityId}:subject-1"),
                                "repeated transient 401 retains credential");
                        }
                    }
                    recovered = true;
                    clock.Advance(outcome.StartsWith("refresh401", StringComparison.Ordinal) ? 900 : 60);
                    await publication.TickAsync(); // outstanding clear, if any
                    // A repeated resource 401 already completed its compensating
                    // clear; its first recovery tick publishes. Another tick is
                    // an ordinary heartbeat, rather than part of that recovery.
                    if (outcome != "repeated401") await publication.TickAsync();
                    AssertEqual("applied", publication.Status.State, "network recovery needs no user action");
                    AssertEqual(outcome == "repeated401" ? 3 : 2, writes, "recovered sharing resumes automatically");
                }
                Console.WriteLine("PASS M04b existing OAuth refresh: " + outcome);
            }
            finally { Directory.Delete(root, true); }
        }
    }
}
