using System.Net;
using StarBridge.HostRuntime.Auth;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task RestoreSingleFlight()
    {
        foreach (var outcome in new[] { "success", "invalid_client", "invalid_grant", "network", "timeout", "5xx" })
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var vault = new RaceVault();
            var key = options.AuthorityId + ":subject-1";
            vault.SaveRefreshToken(key, "synthetic-refresh");
            var refreshes = 0;
            var entered = Signal();
            var release = Signal();
            var recovering = false;
            using var handler = new RaceHandler(async (request, token) => {
                if (request.RequestUri == options.TokenEndpoint)
                {
                    refreshes++;
                    entered.TrySetResult();
                    await release.Task.WaitAsync(token);
                    if (!recovering)
                    {
                        if (outcome == "network") throw new HttpRequestException("Synthetic transport failure");
                        if (outcome == "timeout") throw new TaskCanceledException("Synthetic timeout");
                        if (outcome == "5xx") return JsonResponse(HttpStatusCode.ServiceUnavailable, "{\"error\":\"invalid_grant\"}");
                        if (outcome != "success") return JsonResponse(HttpStatusCode.Unauthorized, "{\"error\":\"" + outcome + "\"}");
                    }
                    return JsonResponse(HttpStatusCode.OK,
                        "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}");
                }
                return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}");
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            var first = oauth.TryRestoreSessionAsync(default);
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            var others = Enumerable.Range(0, 4).Select(_ => oauth.TryRestoreSessionAsync(default)).ToArray();
            using var followerCancellation = new CancellationTokenSource();
            var cancelled = oauth.TryRestoreSessionAsync(followerCancellation.Token);
            followerCancellation.Cancel();
            try { await cancelled; throw new InvalidOperationException("Follower did not cancel"); }
            catch (OperationCanceledException) { }
            release.TrySetResult();
            var successes = 0;
            var temporary = 0;
            foreach (var task in others.Prepend(first))
            {
                try { if (await task.WaitAsync(TimeSpan.FromSeconds(5)) is not null) successes++; }
                catch (Exception error) when (error is HttpRequestException or OperationCanceledException) { temporary++; }
            }
            AssertEqual(1, refreshes, outcome + " shares the in-flight restore, including failure");
            AssertEqual(outcome == "success" ? 5 : 0, successes, outcome + " shared success count");
            AssertEqual(outcome is "success" or "invalid_grant" ? 0 : 5, temporary, outcome + " shared transient count");
            AssertEqual(outcome == "invalid_grant" ? 1 : 0, vault.Deletes, outcome + " deletion count");
            AssertEqual(outcome == "invalid_grant" ? null : key, vault.LoadActiveAccountKey(), outcome + " selected account");
            if (outcome is not "invalid_grant" and not "success")
            {
                recovering = true;
                AssertEqual(true, await oauth.TryRestoreSessionAsync(default) is not null, "later independent call can recover");
                AssertEqual(2, refreshes, "later recovery refreshes once");
            }
            Console.WriteLine($"CX-L07 single-flight {outcome}: joined=5 initial-refreshes=1 deletes={vault.Deletes}");
        }
    }

    internal static async Task Concurrent401AndBackgroundRestore()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        vault.SaveRefreshToken(options.AuthorityId + ":subject-1", "synthetic-refresh");
        var refreshes = 0;
        var entered = Signal();
        var release = Signal();
        using var handler = new RaceHandler(async (request, token) => {
            if (request.RequestUri == options.TokenEndpoint)
            {
                if (++refreshes == 2) { entered.TrySetResult(); await release.Task.WaitAsync(token); }
                return JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access-" + refreshes +
                    "\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}");
            }
            return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}");
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var initial = (await oauth.TryRestoreSessionAsync(default))!;
        var first = oauth.SendResourceRequestAsync(initial, Send, default);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var second = oauth.SendResourceRequestAsync(initial, Send, default);
        var background = oauth.TryRestoreSessionAsync(default);
        release.TrySetResult();
        var firstResult = await first.WaitAsync(TimeSpan.FromSeconds(5));
        var secondResult = await second.WaitAsync(TimeSpan.FromSeconds(5));
        var restored = await background.WaitAsync(TimeSpan.FromSeconds(5));
        AssertEqual(2, refreshes, "two 401 and background restore use one additional refresh");
        AssertEqual(0, vault.Deletes, "concurrent resource reads keep the credential");
        AssertEqual(firstResult.ActiveSession.CredentialVersion, secondResult.ActiveSession.CredentialVersion, "resource version shared");
        AssertEqual(firstResult.ActiveSession.CredentialVersion, restored!.CredentialVersion, "background version shared");
        AssertEqual<Guid?>(restored.CredentialVersion, oauth.CurrentCredentialVersion, "read-only current version");
        AssertEqual(false, initial.CredentialVersion == restored.CredentialVersion, "rotation changes opaque version");
        await UnauthorizedJoiningMemoryRestoreMustRefresh();
        Task<bool> Send(ScmOAuthSession active, CancellationToken _) => active.CredentialVersion == initial.CredentialVersion
            ? Task.FromException<bool>(new ScmApiAuthenticationException("Synthetic resource 401")) : Task.FromResult(true);
    }

    private static async Task UnauthorizedJoiningMemoryRestoreMustRefresh()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        vault.SaveRefreshToken(options.AuthorityId + ":subject-1", "synthetic-refresh");
        var refreshes = 0;
        using var handler = new ScriptedHandler(request => request.RequestUri == options.TokenEndpoint
            ? JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access-" + (++refreshes) +
                "\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}")
            : JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}"));
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var initial = (await oauth.TryRestoreSessionAsync(default))!;
        var gate = (SemaphoreSlim)typeof(OAuthPkceClient).GetField("_refreshGate",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(oauth)!;
        await gate.WaitAsync();
        Task<(bool Result, ScmOAuthSession ActiveSession)> resource;
        Task<ScmOAuthSession?> background;
        var calls = 0;
        try
        {
            background = oauth.TryRestoreSessionAsync(default);
            resource = oauth.SendResourceRequestAsync(initial, (active, _) => {
                calls++;
                return active.CredentialVersion == initial.CredentialVersion
                    ? Task.FromException<bool>(new ScmApiAuthenticationException("Synthetic 401 joins memory restore"))
                    : Task.FromResult(true);
            }, default);
        }
        finally { gate.Release(); }
        await background.WaitAsync(TimeSpan.FromSeconds(5));
        await resource.WaitAsync(TimeSpan.FromSeconds(5));
        AssertEqual(2, refreshes, "joining a same-version memory restore must still refresh the rejected version once");
        AssertEqual(2, calls, "ordinary memory flight followed by real refresh has one resource retry");
        AssertEqual(0, vault.Deletes, "memory restore is not evidence of successful 401 recovery");
    }

    internal static async Task LogoutAndAccountSwitchDoNotResurrect()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        var firstKey = options.AuthorityId + ":subject-1";
        var secondKey = options.AuthorityId + ":subject-2";
        vault.SaveRefreshToken(firstKey, "synthetic-refresh");
        var subject = "subject-1";
        var refreshes = 0;
        using var handler = new ScriptedHandler(request => {
            if (request.RequestUri == options.RevokeEndpoint) return JsonResponse(HttpStatusCode.OK, "{}");
            if (request.RequestUri == options.TokenEndpoint) return JsonResponse(HttpStatusCode.OK,
                "{\"access_token\":\"synthetic-" + (++refreshes) + "\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}");
            return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"" + subject + "\",\"capabilities\":[\"profile.read\"]}");
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var initial = (await oauth.TryRestoreSessionAsync(default))!;
        var entered = Signal();
        var release = Signal();
        ScmOAuthSession? retrySession = null;
        var calls = 0;
        var pending = oauth.SendResourceRequestAsync<bool>(initial, async (active, token) => {
            AssertEqual("subject-1", active.Subject, "old request must never run with switched account");
            if (++calls == 1) throw new ScmApiAuthenticationException("Synthetic first 401");
            retrySession = active;
            entered.TrySetResult();
            await release.Task.WaitAsync(token);
            throw new ScmApiAuthenticationException("Synthetic late retry 401");
        }, default);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await oauth.RevokeAsync(retrySession!, default);
        AssertEqual(1, vault.Deletes, "explicit logout deletes normally");
        AssertEqual<Guid?>(null, oauth.CurrentCredentialVersion, "logout removes current version");
        subject = "subject-2";
        vault.SaveRefreshToken(secondKey, "synthetic-second");
        var replacement = (await oauth.TryRestoreSessionAsync(default))!;
        release.TrySetResult();
        try { await pending; throw new InvalidOperationException("Switched request must be retried by its owner"); }
        catch (ScmRefreshTemporarilyUnavailableException) { }
        AssertEqual(1, vault.Deletes, "late old-account failure cannot delete new account");
        AssertEqual(secondKey, vault.LoadActiveAccountKey(), "new account remains selected");
        AssertEqual<Guid?>(replacement.CredentialVersion, oauth.CurrentCredentialVersion, "old request cannot replace current version");
        AssertEqual(3, refreshes, "old account failure must not refresh new account");
    }
}
