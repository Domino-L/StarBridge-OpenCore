using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;

internal static class ScmCredentialRetirementTests
{
    private const string Owner = "synthetic-authority:synthetic-pilot";
    private const string Token = "synthetic-refresh-only";
    internal static async Task Run()
    {
        Case("actual Windows vault commits an opaque version and clears only that credential", ActualVault);
        Case("a later login for the same owner invalidates the former cleanup receipt", NewSameOwner);
        Case("a different selected account cannot be removed or adopted by cleanup", DifferentOwner);
        Case("storage binding and invalid stamps cannot authorize cleanup", Binding);
        Case("ordinary login, logout and cleanup share one actual writer lease", BusyWriter);
        Case("retained rejection observation preserves credentials under the original writer lease", ObserveRejection);
        Case("cancelled final guards preserve the exact credential and remove only own temporary", FinalGuards);
        Case("malformed, duplicate, oversized and unreadable credential data remains intact", InvalidData);
        Case("legacy plaintext-key entries retain explicit version fencing without migration", LegacyKey);
        await OAuthPreparation();
        Console.WriteLine("PASS first-use credential retirement: preparation requires the actual OAuth credential commit without new traffic");
        await OAuthRefreshVersions();
        Console.WriteLine("PASS first-use credential retirement: actual OAuth refresh advances the cleanup version and rejects former sessions");
        await InterruptedRealRevocation();
        Console.WriteLine("PASS first-use credential retirement: cancelled actual Windows revocation resumes only its own cleared session, never a new login");
    }
    private static void Case(string name, Action run) { run(); Console.WriteLine("PASS first-use credential retirement: " + name); }
    private static void Require(bool value, string reason) { if (!value) throw new InvalidOperationException(reason); }
    private static void Failed(Action run)
    { try { run(); } catch (Exception error) when (error is IOException or InvalidDataException) { return; } throw new InvalidOperationException("Expected a preserved storage failure."); }

    private static void ActualVault()
    {
        using var f = new Fixture();
        var stamp = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        Require(f.Vault.LoadActiveAccountKey() == Owner && f.Vault.LoadRefreshToken(Owner) == Token &&
            f.Vault.CaptureRetirement(Owner) == stamp && f.Vault.IsRetirementCurrent(stamp), "actual committed DPAPI entries");
        var serialized = JsonSerializer.Serialize(stamp);
        Require(!serialized.Contains(Owner, StringComparison.Ordinal) && !serialized.Contains(Token, StringComparison.Ordinal) &&
            !serialized.Contains(f.Path, StringComparison.Ordinal) && stamp.EntriesHash is { Length: 64 }, "receipt contains only opaque storage versions");
        Require(f.Vault.TryClearRetirement(stamp, () => true) && f.Vault.LoadRefreshToken(Owner) is null &&
            f.Vault.LoadActiveAccountKey() is null, "actual stored credential and selected owner are removed");
        var cold = new WindowsTokenVault(f.Path);
        Require(cold.TryClearRetirement(stamp, () => true), "completed original deletion is idempotent without credential restoration");
        var absent = cold.CaptureRetirement(Owner);
        Require(absent.EntriesHash is null && absent.ActiveEntryHash is null && cold.IsRetirementCurrent(absent), "explicit verified absence, not malformed data");
    }

    private static void NewSameOwner()
    {
        using var f = new Fixture();
        var original = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        var otherWriter = new WindowsTokenVault(f.Path);
        var next = otherWriter.SaveRefreshTokenWithRetirement(Owner, "synthetic-new-refresh");
        var bytes = File.ReadAllBytes(f.Path);
        Require(!f.Vault.TryClearRetirement(original, () => true) && !f.Vault.IsRetirementCurrent(original) &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Path)) && f.Vault.LoadRefreshToken(Owner) == "synthetic-new-refresh",
            "a newer exact credential version survives stale cleanup");
        // Even a server reusing the same refresh value must not revive an old
        // storage receipt: the successful new writer owns fresh protected bytes.
        var sameValue = f.Vault.SaveRefreshTokenWithRetirement(Owner, "synthetic-new-refresh");
        Require(next != sameValue && !otherWriter.TryClearRetirement(next, () => true), "same plaintext token is not the same login commit");
        Require(otherWriter.TryClearRetirement(sameValue, () => true), "only the actual new writer's receipt may clear its own credential");
    }

    private static void DifferentOwner()
    {
        using var f = new Fixture();
        var original = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        var other = f.Vault.SaveRefreshTokenWithRetirement("synthetic-authority:synthetic-second", "synthetic-second-refresh");
        var bytes = File.ReadAllBytes(f.Path);
        Require(!f.Vault.TryClearRetirement(original, () => true) && bytes.SequenceEqual(File.ReadAllBytes(f.Path)) &&
            f.Vault.LoadActiveAccountKey() == "synthetic-authority:synthetic-second", "a different selected login remains intact");
        Failed(() => f.Vault.CaptureRetirement(Owner));
        Require(f.Vault.TryClearRetirement(other, () => true) && f.Vault.LoadRefreshToken(Owner) == Token,
            "cleanup of the selected owner preserves unrelated stored accounts");
        Require(!f.Vault.TryClearRetirement(original, () => true), "clearing another login cannot resurrect the former selected-owner version");
    }

    private static void Binding()
    {
        using var f = new Fixture();
        var stamp = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        var otherPath = System.IO.Path.Combine(f.Root, "other-vault.json");
        var other = new WindowsTokenVault(otherPath);
        Require(!other.TryClearRetirement(stamp, () => true) && !File.Exists(otherPath + ".lock"), "wrong configured path cannot even open a cleanup writer");
        Failed(() => f.Vault.TryClearRetirement(stamp with { OwnerKey = "not-a-digest" }, () => true));
        Failed(() => f.Vault.TryClearRetirement(stamp with { EntriesHash = null }, () => true));
        var empty = new WindowsTokenVault(System.IO.Path.Combine(f.Root, "absent-vault.json"));
        var absent = empty.CaptureRetirement(Owner);
        empty.SaveRefreshToken(Owner, Token);
        Require(!empty.TryClearRetirement(absent, () => true) && empty.LoadRefreshToken(Owner) == Token,
            "an earlier missing credential is not authority to delete a later login");
    }

    private static void ObserveRejection()
    {
        using var f = new Fixture();
        var stamp = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        var bytes = File.ReadAllBytes(f.Path);
        var observations = 0;
        Require(!f.Vault.ObserveCurrentRetirement(stamp, () => false, () => observations++),
            "a cancelled mode cannot observe rejection");
        var replacementBlocked = false;
        Require(f.Vault.ObserveCurrentRetirement(stamp, () => true, () =>
        {
            observations++;
            try { new WindowsTokenVault(f.Path).SaveRefreshToken(Owner, "synthetic-concurrent"); }
            catch (IOException) { replacementBlocked = true; }
        }), "original selected version must permit the bounded observation");
        Require(observations == 1 && replacementBlocked && bytes.SequenceEqual(File.ReadAllBytes(f.Path)) &&
            f.Vault.LoadRefreshToken(Owner) == Token, "observation must preserve bytes and exclude a new login throughout its callback");
        f.Vault.SaveRefreshToken(Owner, "synthetic-later");
        Require(!f.Vault.ObserveCurrentRetirement(stamp, () => true, () => observations++) && observations == 1 &&
            f.Vault.LoadRefreshToken(Owner) == "synthetic-later", "stale rejection cannot observe or alter a later same-owner credential");
    }

    private static void BusyWriter()
    {
        using var f = new Fixture();
        var stamp = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        var bytes = File.ReadAllBytes(f.Path);
        using (var writer = new FileStream(f.Path + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            Failed(() => f.Vault.SaveRefreshToken(Owner, "synthetic-new-refresh"));
            Failed(() => f.Vault.DeleteRefreshToken(Owner));
            Failed(() => f.Vault.CaptureRetirement(Owner));
            Failed(() => f.Vault.TryClearRetirement(stamp, () => true));
            Require(bytes.SequenceEqual(File.ReadAllBytes(f.Path)), "no writer bypasses a busy real credential lease");
        }
        f.Vault.SaveRefreshToken(Owner, "synthetic-new-refresh");
        Require(!f.Vault.TryClearRetirement(stamp, () => true), "released writer does not refresh stale cleanup authority");
        var current = f.Vault.CaptureRetirement(Owner);
        var committed = 0;
        Require(f.Vault.TryClearRetirement(current, () => true, () => {
            Failed(() => new WindowsTokenVault(f.Path).SaveRefreshToken(Owner, "synthetic-login-during-mode-commit"));
            Require(f.Vault.IsRetirementCleared(current), "mode commit sees actual clear under the original writer lease");
            committed++;
        }) && committed == 1, "a new login cannot interleave between actual clear and its dependent mode commit");
    }

    private static void FinalGuards()
    {
        using var f = new Fixture();
        var stamp = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        var bytes = File.ReadAllBytes(f.Path);
        Require(!f.Vault.TryClearRetirement(stamp, () => false), "closed admission does not mutate credentials");
        var checks = 0;
        Require(!f.Vault.TryClearRetirement(stamp, () => ++checks < 4) && checks == 4 &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Path)) && Directory.GetFiles(f.Root, "*.tmp").Length == 0,
            "late owner/cancellation guard retains bytes after a prepared atomic write");
        checks = 0;
        Require(!f.Vault.TryClearRetirement(stamp, () => {
            if (++checks == 4) File.WriteAllText(f.Path, "{\"synthetic-unrelated\":\"opaque-unknown\"}");
            return true;
        }) && File.ReadAllText(f.Path).Contains("synthetic-unrelated", StringComparison.Ordinal),
            "an external writer not following the lease cannot be overwritten by the prepared cleanup");
    }

    private static void InvalidData()
    {
        using var f = new Fixture();
        var stamp = f.Vault.SaveRefreshTokenWithRetirement(Owner, Token);
        foreach (var text in new[] { "not-json", "null", "{}{}", "{\"x\":\"a\",\"x\":\"b\"}", "{\"x\":null}", "" })
        {
            File.WriteAllText(f.Path, text);
            var bytes = File.ReadAllBytes(f.Path);
            Failed(() => f.Vault.SaveRefreshToken(Owner, Token));
            Failed(() => f.Vault.DeleteRefreshToken(Owner));
            Failed(() => f.Vault.CaptureRetirement(Owner));
            Failed(() => f.Vault.TryClearRetirement(stamp, () => true));
            Require(bytes.SequenceEqual(File.ReadAllBytes(f.Path)), "unreadable vault is not empty or disposable");
        }
        File.WriteAllBytes(f.Path, new byte[1_048_577]);
        var oversized = SHA256.HashData(File.ReadAllBytes(f.Path));
        Failed(() => f.Vault.TryClearRetirement(stamp, () => true));
        Require(oversized.SequenceEqual(SHA256.HashData(File.ReadAllBytes(f.Path))), "oversized original remains intact");
        // Only this independently owned synthetic fixture is replaced to proceed.
        File.WriteAllText(f.Path, "{}");
        f.Vault.SaveRefreshToken(Owner, Token);
        var values = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(f.Path))!;
        values["account:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Owner)))] = "AA==";
        File.WriteAllText(f.Path, JsonSerializer.Serialize(values));
        var damaged = File.ReadAllBytes(f.Path);
        Failed(() => f.Vault.CaptureRetirement(Owner));
        Require(!f.Vault.TryClearRetirement(stamp, () => true) && damaged.SequenceEqual(File.ReadAllBytes(f.Path)),
            "an unverifiable protected entry is not silently cleared by a former receipt");
    }

    private static void LegacyKey()
    {
        using var f = new Fixture();
        foreach (var owner in new[] { Owner, "account:synthetic-pilot", "account:" + new string('a', 64) })
        {
            f.Vault.SaveRefreshToken(owner, Token);
            var values = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(f.Path))!;
            var hashed = "account:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(owner)));
            values[owner] = values[hashed]; values.Remove(hashed);
            File.WriteAllText(f.Path, JsonSerializer.Serialize(values));
            var bytes = File.ReadAllBytes(f.Path);
            var stamp = f.Vault.CaptureRetirement(owner);
            Require(f.Vault.LoadRefreshToken(owner) == Token && bytes.SequenceEqual(File.ReadAllBytes(f.Path)), "capture does not promote or rewrite an older key");
            Require(f.Vault.TryClearRetirement(stamp, () => true) && f.Vault.LoadRefreshToken(owner) is null,
                "explicit exact-version logout removes the matching older key, not other accounts");
        }
    }

    private static async Task OAuthPreparation()
    {
        using var f = new Fixture();
        f.Vault.SaveRefreshToken(Owner, Token);
        var endpoint = new Uri("https://auth.example.invalid/");
        var options = new ScmOAuthOptions("synthetic-authority", endpoint, endpoint, endpoint, "synthetic-client", "synthetic-resource", "profile.read", "/callback");
        using var transport = new OAuthTransport(options);
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), f.Vault, options);
        var preloaded = new ScmOAuthSession(options.AuthorityId, "synthetic-pilot", "Synthetic Pilot", "synthetic-preloaded", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        try { await oauth.PrepareCredentialRetirementAsync(preloaded, default); throw new InvalidOperationException("Expected missing original stamp"); }
        catch (ScmRefreshTemporarilyUnavailableException) { }
        Require(transport.Requests == 0,
            "a preloaded session without the original stamp remains temporary and cannot restore itself");
        var session = (await oauth.TryRestoreSessionAsync(default))!;
        var traffic = transport.Requests;
        var prepared = await oauth.PrepareCredentialRetirementAsync(session, default);
        Require(prepared is not null && f.Vault.IsRetirementCurrent(prepared) && transport.Requests == traffic,
            "actual verified OAuth session owns the exact committed protected credential version");
        var bytes = File.ReadAllBytes(f.Path);
        await InvalidPreparation<InvalidDataException>(() => oauth.PrepareCredentialRetirementAsync(session with { Subject = "synthetic-other" }, default));
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            try { await oauth.PrepareCredentialRetirementAsync(session, cancelled.Token); throw new InvalidOperationException("Expected cancellation"); }
            catch (OperationCanceledException) { }
        }
        Require(bytes.SequenceEqual(File.ReadAllBytes(f.Path)) && transport.Requests == traffic, "changed owner and cancellation do not mutate or refresh credentials");
        new WindowsTokenVault(f.Path).SaveRefreshToken(Owner, "synthetic-later-login");
        bytes = File.ReadAllBytes(f.Path);
        await InvalidPreparation<ScmRefreshTemporarilyUnavailableException>(() => oauth.PrepareCredentialRetirementAsync(session, default));
        try { await oauth.RevokeAsync(session, default); throw new InvalidOperationException("Expected changed credential version"); }
        catch (ScmLocalCredentialRetirementException error) when (error.InnerException is ScmRefreshTemporarilyUnavailableException) { }
        Require(bytes.SequenceEqual(File.ReadAllBytes(f.Path)) && transport.Requests == traffic &&
            !f.Vault.TryClearRetirement(prepared!, () => true), "original OAuth owner cannot capture or clear a different writer's login version");
    }

    private static async Task OAuthRefreshVersions()
    {
        using var f = new Fixture();
        f.Vault.SaveRefreshToken(Owner, Token);
        var endpoint = new Uri("https://auth.example.invalid/");
        var options = new ScmOAuthOptions("synthetic-authority", endpoint, endpoint, endpoint, "synthetic-client", "synthetic-resource", "profile.read", "/callback");
        using var transport = new OAuthTransport(options);
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), f.Vault, options);
        var initial = (await oauth.TryRestoreSessionAsync(default))!;
        var former = (await oauth.PrepareCredentialRetirementAsync(initial, default))!;
        var refreshed = await oauth.SendResourceRequestAsync(initial, (active, _) => active.AccessToken == initial.AccessToken
            ? Task.FromException<bool>(new ScmApiAuthenticationException("Synthetic unauthorized response")) : Task.FromResult(true), default);
        var actual = (await oauth.PrepareCredentialRetirementAsync(refreshed.ActiveSession, default))!;
        Require(transport.Refreshes == 2 && actual != former && !f.Vault.TryClearRetirement(former, () => true),
            "normal actual refresh mints a new storage version and preserves it from stale cleanup");
        var traffic = transport.Requests;
        await InvalidPreparation<ScmRefreshTemporarilyUnavailableException>(() => oauth.PrepareCredentialRetirementAsync(initial, default));
        Require(transport.Requests == traffic && f.Vault.TryClearRetirement(actual, () => true),
            "only the current actual session's version can be prepared and removed without another network request");
    }

    private static async Task InvalidPreparation<T>(Func<Task<ScmCredentialRetirementStamp?>> run) where T : Exception
    { try { await run(); } catch (Exception error) when (error.GetType() == typeof(T)) { return; } throw new InvalidOperationException("Expected exact preparation failure: " + typeof(T).Name); }

    private static async Task InterruptedRealRevocation()
    {
        foreach (var newLogin in new[] { false, true })
        {
            using var f = new Fixture();
            f.Vault.SaveRefreshToken(Owner, Token);
            var endpoint = new Uri("https://auth.example.invalid/");
            var options = new ScmOAuthOptions("synthetic-authority", endpoint, endpoint, endpoint, "synthetic-client", "synthetic-resource", "profile.read", "/callback");
            using var transport = new OAuthTransport(options);
            var oauth = new OAuthPkceClient(new ScmHttpClient(transport), f.Vault, options);
            var session = (await oauth.TryRestoreSessionAsync(default))!;
            using var cancelled = new CancellationTokenSource();
            transport.RevokeReached = () => { cancelled.Cancel(); throw new OperationCanceledException(cancelled.Token); };
            try { await oauth.RevokeAsync(session, cancelled.Token); throw new InvalidOperationException("Expected cancellation"); }
            catch (OperationCanceledException) { }
            Require(f.Vault.LoadActiveAccountKey() is null && f.Vault.LoadRefreshToken(Owner) is null,
                "original real credential was cleared before the cancelled remote revoke");
            var traffic = transport.Requests;
            transport.RevokeReached = null;
            if (newLogin)
            {
                new WindowsTokenVault(f.Path).SaveRefreshToken(Owner, "synthetic-new-login-after-clear");
                var bytes = File.ReadAllBytes(f.Path);
                try { await oauth.RevokeAsync(session, default); throw new InvalidOperationException("Expected changed original credential"); }
                catch (ScmLocalCredentialRetirementException error) when (error.InnerException is InvalidDataException) { }
                Require(bytes.SequenceEqual(File.ReadAllBytes(f.Path)) && transport.Requests == traffic,
                    "absence at an earlier attempt cannot authorize clearing a subsequent login");
            }
            else
            {
                await oauth.RevokeAsync(session, default);
                Require(transport.Requests == traffic && f.Vault.LoadRefreshToken(Owner) is null,
                    "actual original-session retry does not restore, rewrite or remotely revoke credentials again");
            }
        }
    }

    private sealed class OAuthTransport(ScmOAuthOptions options) : HttpMessageHandler
    {
        internal int Requests, Refreshes;
        internal Action? RevokeReached;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested(); Requests++;
            string json;
            if (request.RequestUri == options.TokenEndpoint)
            {
                Refreshes++;
                json = "{\"access_token\":\"synthetic-access-" + Refreshes + "\",\"refresh_token\":\"synthetic-refresh-" + Refreshes +
                    "\",\"token_type\":\"Bearer\",\"expires_in\":3600}";
            }
            else if (request.RequestUri == options.RevokeEndpoint)
            {
                RevokeReached?.Invoke();
                json = "{}";
            }
            else if (request.RequestUri == options.MeEndpoint)
                json = "{\"subject\":\"synthetic-pilot\",\"displayName\":\"Synthetic Pilot\",\"capabilities\":[\"profile.read\"]}";
            else throw new InvalidOperationException("Unexpected synthetic OAuth request");
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            });
        }
    }

    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "starbridge-credential-retirement", Guid.NewGuid().ToString("N"));
        internal string Path => System.IO.Path.Combine(Root, "vault.json");
        internal WindowsTokenVault Vault { get; }
        private readonly string _previousRoot;
        internal Fixture()
        {
            CheckRoot(); Directory.CreateDirectory(Root); Vault = new(Path);
            _previousRoot = StarBridge.HostRuntime.HostDataRoot.CurrentRoot;
            StarBridge.HostRuntime.HostDataRoot.UsePreparedRoot(Root);
        }
        public void Dispose()
        {
            StarBridge.HostRuntime.HostDataRoot.UsePreparedRoot(_previousRoot);
            CheckRoot(); Directory.Delete(Root, recursive: true);
        }
        private void CheckRoot()
        {
            var full = System.IO.Path.GetFullPath(Root);
            var parent = System.IO.Path.GetFullPath(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "starbridge-credential-retirement"));
            if (System.IO.Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(System.IO.Path.GetFileName(full), "N", out _))
                throw new InvalidOperationException("Unsafe fixture target.");
            for (var node = full; node is not null; node = System.IO.Path.GetDirectoryName(node))
            {
                FileAttributes attributes;
                try { attributes = File.GetAttributes(node); }
                catch (FileNotFoundException) { continue; }
                catch (DirectoryNotFoundException) { continue; }
                if (attributes.HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture target.");
            }
        }
    }
}
