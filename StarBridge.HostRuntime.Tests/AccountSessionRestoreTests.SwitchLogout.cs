using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    private static async Task SwitchLogoutReview()
    {
        var cases = new (string Name, Func<Task> Run)[] {
            ("Windows switch removes A", () => SwitchLogin("switch", true)),
            ("simple vault switch removes A", () => SwitchLogin("switch", false)),
            ("concurrent A replacement survives", () => SwitchLogin("replace", true)),
            ("simple concurrent A replacement survives", () => SwitchLogin("replace", false)),
            ("delete failure does not reject B", () => SwitchLogin("delete-fail", false)),
            ("same owner keeps new credential", () => SwitchLogin("same", true)),
            ("cancelled login preserves A", () => SwitchLogin("cancel", true)),
            ("failed login preserves A", () => SwitchLogin("fail", true)),
            ("startup removes only unselected", StartupUnselectedCleanup),
            ("Host missing stamp cannot sign out", () => HostLogoutBoundary("missing")),
            ("Host changed writer cannot sign out", () => HostLogoutBoundary("changed")),
            ("Host failed local clear cannot sign out", () => HostLogoutBoundary("busy")),
            ("Host remote failure after local clear signs out", () => HostLogoutBoundary("remote"))
        };
        var failures = new List<string>();
        foreach (var (name, run) in cases)
        {
            try { await run(); Console.WriteLine("PASS CX-L07c " + name); }
            catch (Exception error) { failures.Add(name); Console.WriteLine("FAIL CX-L07c " + name + ": " + error.Message); }
        }
        Console.WriteLine($"CX-L07c SUMMARY PASS {cases.Length - failures.Count}/{cases.Length} FAIL {failures.Count}");
        if (failures.Count != 0) throw new InvalidOperationException("CX-L07c failures: " + string.Join(", ", failures));
    }

    private static async Task SwitchLogin(string scenario, bool windows)
    {
        var root = Path.Combine(HostDataRoot.CurrentRoot, "l07c-switch-" + Guid.NewGuid().ToString("N"));
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var path = Path.Combine(root, "vault.json");
        ITokenVault vault = windows ? new WindowsTokenVault(path) : scenario == "delete-fail" ? new DeleteFailureVault() : new RaceVault();
        var key = options.AuthorityId + ":subject-1";
        vault.SaveRefreshToken(key, "synthetic-original");
        var subject = scenario == "same" ? "subject-1" : "subject-2";
        var login = false;
        using var cancel = new CancellationTokenSource();
        using var handler = new ScriptedHandler(request => {
            if (request.RequestUri == options.TokenEndpoint)
            {
                if (login && scenario == "fail") throw new HttpRequestException("Synthetic failure");
                return JsonResponse(HttpStatusCode.OK, ReviewToken);
            }
            return ReviewIdentity(login ? subject : "subject-1");
        });
        Task? callback = null;
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options, authorizationBrowser: authorization => {
            if (scenario == "replace")
            {
                ITokenVault writer = windows ? new WindowsTokenVault(path) : vault;
                writer.SaveRefreshToken(key, "synthetic-other-writer");
            }
            if (scenario == "cancel") { cancel.Cancel(); return; }
            var query = authorization.Query.TrimStart('?').Split('&').Select(value => value.Split('=', 2))
                .ToDictionary(value => Uri.UnescapeDataString(value[0]), value => Uri.UnescapeDataString(value[1]));
            var uri = new Uri(query["redirect_uri"] + "?code=synthetic-code&state=" + Uri.EscapeDataString(query["state"]));
            if (!uri.IsLoopback) throw new InvalidOperationException("Only synthetic loopback callback allowed");
            callback = LocalCallback(uri);
        });
        await oauth.TryRestoreSessionAsync(default);
        var oldBytes = windows ? File.ReadAllBytes(path) : null;
        login = true;
        try
        {
            await oauth.SignInAsync(cancel.Token);
            AssertEqual(false, scenario is "cancel" or "fail", "unsuccessful login must not commit");
        }
        catch (OperationCanceledException) when (scenario == "cancel") { }
        catch (HttpRequestException) when (scenario == "fail") { }
        if (callback is not null) await callback;
        if (scenario is "cancel" or "fail")
        {
            AssertEqual(key, vault.LoadActiveAccountKey(), "unsuccessful login preserves selection");
            AssertEqual("synthetic-next", vault.LoadRefreshToken(key), "unsuccessful login preserves A credential");
            if (windows) AssertEqual(true, oldBytes!.SequenceEqual(File.ReadAllBytes(path)), "no early credential mutation");
            return;
        }
        AssertEqual(options.AuthorityId + ":" + subject, vault.LoadActiveAccountKey(), "B selected");
        AssertEqual("synthetic-next", vault.LoadRefreshToken(options.AuthorityId + ":" + subject), "new credential retained");
        AssertEqual(scenario is "same" or "delete-fail" ? "synthetic-next" : scenario == "replace" ? "synthetic-other-writer" : null,
            vault.LoadRefreshToken(key), "only the original A version may be removed");
    }

    private sealed class DeleteFailureVault : ITokenVault
    {
        private readonly RaceVault _inner = new();
        public void SaveRefreshToken(string key, string token) => _inner.SaveRefreshToken(key, token);
        public string? LoadRefreshToken(string key) => _inner.LoadRefreshToken(key);
        public string? LoadActiveAccountKey() => _inner.LoadActiveAccountKey();
        public void DeleteRefreshToken(string key) => throw new IOException("Synthetic cleanup write failure");
    }

    private static async Task StartupUnselectedCleanup()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var path = Path.Combine(HostDataRoot.CurrentRoot, "l07c-startup-" + Guid.NewGuid().ToString("N"), "vault.json");
        var vault = new WindowsTokenVault(path);
        var old = options.AuthorityId + ":old";
        var selected = options.AuthorityId + ":subject-1";
        vault.SaveRefreshToken(old, "synthetic-unselected");
        vault.SaveRefreshToken(selected, "synthetic-selected");
        // Hold the transport after startup cleanup, before any token rotation.
        using var handler = new ScriptedHandler(_ => throw new HttpRequestException("Synthetic offline startup"));
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(path), options);
        try { await oauth.TryRestoreSessionAsync(default); } catch (HttpRequestException) { }
        AssertEqual<string?>(null, vault.LoadRefreshToken(old), "startup removes unselected leftover");
        AssertEqual("synthetic-selected", vault.LoadRefreshToken(selected), "startup never touches active credential");
        AssertEqual(selected, vault.LoadActiveAccountKey(), "startup preserves active selection");
        vault.SaveRefreshToken(old, "synthetic-later");
        vault.SaveRefreshToken(selected, "synthetic-selected-again");
        try { await oauth.TryRestoreSessionAsync(default); } catch (HttpRequestException) { }
        AssertEqual("synthetic-later", vault.LoadRefreshToken(old), "cleanup runs once per startup owner");
    }

    private static async Task HostLogoutBoundary(string scenario)
    {
        var root = Path.Combine(HostDataRoot.CurrentRoot, "l07c-logout-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(root, "vault.json");
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var key = options.AuthorityId + ":subject-1";
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(key, "synthetic-original");
        var revokes = 0;
        using var handler = new ScriptedHandler(request => {
            if (request.RequestUri == options.RevokeEndpoint) { revokes++; throw new HttpRequestException("Synthetic remote failure"); }
            return request.RequestUri == options.TokenEndpoint ? JsonResponse(HttpStatusCode.OK, ReviewToken) : ReviewIdentity();
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var session = scenario == "missing" ? new ScmOAuthSession(options.AuthorityId, "subject-1", "Synthetic",
            "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]) : (await oauth.TryRestoreSessionAsync(default))!;
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(root), "development", () => null, session, 9);
        using var runtime = new AccountBridgeRuntime(host);
        var context = host.CurrentContext!;
        if (scenario == "changed") new WindowsTokenVault(path).SaveRefreshToken(key, "synthetic-other-writer");
        var bytes = File.ReadAllBytes(path);
        using var writer = scenario == "busy" ? new FileStream(path + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None) : null;
        var result = await runtime.DispatchAsync(BridgeEnvelope.Request("account.logout", "synthetic-logout", 9,
            new { schemaVersion = 1 }, context));
        if (scenario == "remote")
        {
            AssertEqual("ok", result.Response.Status, "committed local logout tolerates remote failure");
            AssertEqual<BridgeAccountContext?>(null, host.CurrentContext, "committed logout clears projection");
            AssertEqual<string?>(null, vault.LoadActiveAccountKey(), "local active credential gone");
            AssertEqual<string?>(null, vault.LoadRefreshToken(key), "local refresh credential gone");
            AssertEqual(10L, runtime.Generation, "one actual sign-out transition");
            AssertEqual(1, revokes, "best effort remote attempt");
        }
        else
        {
            AssertEqual("error", result.Response.Status, "uncommitted local retirement cannot report success");
            AssertEqual("account.logout_incomplete", result.Response.Error?.Code, "actionable logout failure code");
            AssertEqual(true, result.Response.Error?.Retryable, "logout failure permits retry");
            AssertEqual(context, host.CurrentContext, "failed local logout keeps authenticated projection");
            AssertEqual(9L, runtime.Generation, "failed logout does not advance generation");
            AssertEqual(true, bytes.SequenceEqual(File.ReadAllBytes(path)), "failed logout preserves exact credential version");
            AssertEqual(0, revokes, "local failure never reaches remote revocation");
        }
    }
}
