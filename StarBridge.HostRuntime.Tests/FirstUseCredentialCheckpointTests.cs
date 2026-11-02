using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class FirstUseCredentialCheckpointTests
{
    private const string Account = "synthetic-checkpoint:synthetic-pilot";
    private static string Op() => Guid.NewGuid().ToString("N");
    private static string CheckpointPath(string root) => Path.Combine(root, "first-use-mode-v1", "credential-clear.bin");
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static Task<AccountBridgeRuntime> NoOnline(CancellationToken _) => throw new InvalidOperationException("Recovery cannot construct an account/OAuth/network owner.");
    private static async Task Expect(string code, Func<Task> work)
    { try { await work(); } catch (LocalFirstUseException error) when (error.Code == code) { return; } throw new InvalidOperationException("Expected " + code); }
    private static async Task Case(string name, Func<Task> work)
    { await work(); Console.WriteLine("PASS first-use credential checkpoint: " + name); }

    internal static async Task Run()
    {
        await Case("live original owner retains a distinct checkpoint and explicitly finishes its own logout", LiveOwner);
        await Case("a real exited owner permits exact credential clear, never implicit restore", () => ColdClear("beforeClear"));
        await Case("a clear interrupted by remote cancellation remains explicitly recoverable after actual exit", () => ColdClear("afterClear"));
        await Case("known development and local vaults retain exact in-root storage binding", async () => { await ColdClear("development"); await ColdClear("local"); });
        await Case("new same-account login survives the old pending recovery", () => NewLogin(false));
        await Case("a different selected login survives the old pending recovery", () => NewLogin(true));
        await Case("a failed final mode commit retains the actual clear and safely retries", FailedCommit);
        await Case("cancelled and busy recovery preserve the pending intent and credential", BusyAndCancelled);
        await Case("unconfirmed publication cannot create a credential checkpoint", PublicationPending);
        await Case("strict corrupted, incomplete and unrelated checkpoint evidence is preserved", StrictDocuments);
        await Case("checkpoint commit guards and unknown vault bindings do not authorize local mode", GuardsAndBinding);
    }

    internal static async Task WriteChild(string root, string scenario)
    {
        using var f = new Fixture(root, preserve: true);
        await f.CreateAccount(scenario == "wrongPath", fileName: scenario is "development" or "local" ? "scm-token-vault." + scenario + ".json" : null);
        var store = new FirstUseModeStore(f.Root);
        if (scenario == "afterClear")
        {
            using var cancel = new CancellationTokenSource();
            f.Transport.Revoke = () => { cancel.Cancel(); throw new OperationCanceledException(cancel.Token); };
            try { await f.Runtime!.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host!.Generation, cancel.Token); throw new InvalidOperationException("Expected cancelled remote revoke"); }
            catch (OperationCanceledException) { }
            Require(f.Vault.LoadActiveAccountKey() is null, "child really cleared its own credential");
        }
        else
        {
            var pending = store.Save(0, Op(), "localPending", () => true);
            var stopped = await f.Runtime!.StopAccountForLocalModeAsync(f.Host!.Generation, default, (facts, credential, current) => {
                store.SaveCredentialCheckpoint(pending, facts, credential, current);
                throw new IOException("Synthetic interruption before original credential clear");
            });
            Require(stopped.State == "unavailable" && f.Vault.LoadRefreshToken(Account) is not null, "original credential remains after actual reader retirement");
        }
        var saved = store.ReadCredentialCheckpoint();
        Require(store.Read().Phase == "localPending" && saved?.IsFor(store.Read()) == true &&
            saved.Owner.ProcessId == Environment.ProcessId && saved.Owner.ReadExit() == "running" && store.ReadRetirement() is null,
            "child records actual partial retirement, not completed sign-out booleans");
    }

    private static async Task Child(Fixture f, string scenario = "beforeClear")
    {
        var assembly = typeof(FirstUseCredentialCheckpointTests).Assembly.Location;
        var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = Path.GetDirectoryName(assembly)! };
        start.ArgumentList.Add(assembly); start.ArgumentList.Add("--first-use-credential-checkpoint-child");
        start.ArgumentList.Add(f.Root); start.ArgumentList.Add(scenario);
        using var child = Process.Start(start) ?? throw new InvalidOperationException("Could not start fixture child");
        var output = child.StandardOutput.ReadToEndAsync(); var errors = child.StandardError.ReadToEndAsync();
        await child.WaitForExitAsync(); // Keep the live handle; never restart on an observation timeout.
        Require(child.ExitCode == 0, "fixture child failed: " + await output + await errors);
        var checkpoint = new FirstUseModeStore(f.Root).ReadCredentialCheckpoint()!;
        Require(checkpoint.Owner.ProcessId == child.Id && checkpoint.Owner.ReadExit() == "exited", "actual child exit matches original checkpoint owner");
    }

    private static async Task LiveOwner()
    {
        using var f = new Fixture(); await f.CreateAccount();
        using var cancel = new CancellationTokenSource();
        f.Transport.Revoke = () => { cancel.Cancel(); throw new OperationCanceledException(cancel.Token); };
        try { await f.Runtime!.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host!.Generation, cancel.Token); }
        catch (OperationCanceledException) { }
        var store = new FirstUseModeStore(f.Root);
        var checkpoint = store.ReadCredentialCheckpoint()!;
        Require(checkpoint.IsFor(store.Read()) && store.ReadRetirement() is null && f.Host!.CurrentContext is not null && !f.Runtime!.FirstUseMode!.LocalMode().Active,
            "actual local clear alone is not a signed-out mode receipt");
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require((await cold.FirstUseMode!.RecoverLocalAsync(1, Op())).State == "ownerRunning", "live original process cannot be replaced");
        f.Transport.Revoke = null;
        var traffic = f.Transport.Requests;
        Require((await f.Runtime!.FirstUseMode!.ApplyLocalAsync(1, Op(), f.Host!.Generation)).State == "local" &&
            f.Transport.Requests == traffic && f.Host.CurrentContext is null && store.ReadRetirement() is not null,
            "actual original retry completes its own logout without repeating revoke or restoring a token");
    }

    private static async Task ColdClear(string scenario)
    {
        using var f = new Fixture(); await Child(f, scenario);
        var originalVault = scenario is "development" or "local" ? new WindowsTokenVault(Path.Combine(f.Root, "scm-token-vault." + scenario + ".json")) : f.Vault;
        var prior = File.ReadAllBytes(CheckpointPath(f.Root));
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require(cold.FirstUseMode!.Current.State == "recoveryRequired" && !cold.FirstUseMode.LocalMode().Active,
            "opening the blocked runtime performs no implicit clear or mode switch");
        Require((await cold.FirstUseMode.RecoverLocalAsync(1, Op())).State == "local" && cold.FirstUseMode.LocalMode().Active &&
            originalVault.LoadActiveAccountKey() is null && originalVault.LoadRefreshToken(Account) is null && f.Transport.Requests == 0 &&
            prior.SequenceEqual(File.ReadAllBytes(CheckpointPath(f.Root))), "explicit recovery clears only original version and retains private evidence without network");
    }

    private static async Task NewLogin(bool different)
    {
        using var f = new Fixture(); await Child(f);
        f.Vault.SaveRefreshToken(different ? "synthetic-checkpoint:synthetic-other" : Account, "synthetic-new-login");
        var bytes = File.ReadAllBytes(f.VaultPath);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require((await cold.FirstUseMode!.RecoverLocalAsync(1, Op())).State == "recoveryRequired" &&
            !cold.FirstUseMode.LocalMode().Active && bytes.SequenceEqual(File.ReadAllBytes(f.VaultPath)) && f.Transport.Requests == 0,
            "a later selected credential cannot be adopted, deleted or called a completed local mode");
    }

    private static async Task FailedCommit()
    {
        using var f = new Fixture(); await Child(f);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        var state = Path.Combine(f.Root, "first-use-mode-v1", "state.bin");
        var pending = File.ReadAllBytes(state);
        using (var lease = new FileStream(state + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await Expect("firstUse.mode_write_failed", () => cold.FirstUseMode!.RecoverLocalAsync(1, Op()));
        Require(f.Vault.LoadActiveAccountKey() is null && pending.SequenceEqual(File.ReadAllBytes(state)) &&
            !cold.FirstUseMode!.LocalMode().Active, "failed final commit leaves actual clear and original pending intent, not local readiness");
        Require((await cold.FirstUseMode!.RecoverLocalAsync(1, Op())).State == "local", "explicit retry finishes idempotently without restoring authorization");
    }

    private static async Task BusyAndCancelled()
    {
        using var f = new Fixture(); await Child(f);
        var bytes = File.ReadAllBytes(f.VaultPath);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        using (var cancel = new CancellationTokenSource())
        {
            cancel.Cancel();
            try { await cold.FirstUseMode!.RecoverLocalAsync(1, Op(), cancel.Token); throw new InvalidOperationException("Expected cancellation"); }
            catch (OperationCanceledException) { }
        }
        using (var lease = new FileStream(f.VaultPath + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await Expect("firstUse.mode_receipt_write_failed", () => cold.FirstUseMode!.RecoverLocalAsync(1, Op()));
        Require(bytes.SequenceEqual(File.ReadAllBytes(f.VaultPath)) && !cold.FirstUseMode!.LocalMode().Active,
            "cancelled or busy credential clear preserves authorization and does not acknowledge local mode");
    }

    private static async Task PublicationPending()
    {
        using var f = new Fixture(); await f.CreateAccount(publication: true);
        var context = f.Host!.CurrentContext!;
        var settings = f.Privacy!.Save(context, 0, Op(), LocalPrivacySettings.EditorDefaults, () => true);
        var applied = await f.Runtime!.DispatchAsync(BridgeEnvelope.Request("privacy.applyPublication", Op(), f.Host.Generation,
            new { schemaVersion = 1, expectedRevision = settings.Revision }, context));
        var publisher = PrivacyPublicationTestAccess.Ordinary(f.Runtime);
        Require(applied.Response.Error is null && applied.Response.Payload.GetProperty("state").GetString() == "reconnecting" && publisher.ClearPending,
            "actual publisher must retain an unconfirmed withdrawal before testing retirement");
        var failed = await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation);
        Require(publisher.ClearPending && publisher.Status.State == "withdrawalPending",
            "retirement cannot hide its unconfirmed clear behind automatic recovery");
        Require(failed.State == "publicationPending" && !File.Exists(CheckpointPath(f.Root)) && f.Vault.LoadActiveAccountKey() == Account,
            "unconfirmed withdrawal preserves the credential and never creates a ready-to-clear checkpoint");
        f.Transport.WithdrawalAllowed = true;
        f.Transport.BeforeWithdrawal = () => Require(f.Vault.LoadActiveAccountKey() == Account && !File.Exists(CheckpointPath(f.Root)),
            "withdrawal must precede credential checkpoint and clear");
        f.Transport.Revoke = () => throw new IOException("Synthetic interruption after local clear");
        f.Host.ConfigurePrivacyWriter(new PrivacyRelayWriter(new Uri("https://relay.example.invalid/"), f.Transport));
        var retry = await f.Runtime.FirstUseMode.ApplyLocalAsync(1, Op(), f.Host.Generation);
        Require(retry.State == "unavailable" && f.Transport.Withdrawals == 1 &&
            new FirstUseModeStore(f.Root).ReadCredentialCheckpoint() is { PublicationStopped: true } &&
            !f.Runtime.FirstUseMode.LocalMode().Active, "only real validated withdrawal permits a pending credential checkpoint, not mode completion");
    }

    private static async Task StrictDocuments()
    {
        using var f = new Fixture(); await Child(f);
        var store = new FirstUseModeStore(f.Root); var checkpoint = store.ReadCredentialCheckpoint()!;
        var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var originals = File.ReadAllBytes(CheckpointPath(f.Root));
        foreach (var document in new[] { "{}", "{\"schemaVersion\":1,\"schemaVersion\":1}",
            JsonSerializer.Serialize(new { schemaVersion = 1, value = checkpoint with { PublicationStopped = false } }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = checkpoint with { Credential = checkpoint.Credential with { OwnerKey = "bad" } } }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = checkpoint, extra = true }, json) })
        {
            var bytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(document), Encoding.UTF8.GetBytes("StarBridge.first-use-credential-clear.v1"), DataProtectionScope.CurrentUser);
            File.WriteAllBytes(CheckpointPath(f.Root), bytes);
            using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
            await Expect("firstUse.mode_receipt_read_failed", () => cold.FirstUseMode!.RecoverLocalAsync(1, Op()));
            Require(bytes.SequenceEqual(File.ReadAllBytes(CheckpointPath(f.Root))) && f.Vault.LoadActiveAccountKey() == Account,
                "malformed proof is not erased, repaired or used to clear credentials");
        }
        File.WriteAllBytes(CheckpointPath(f.Root), originals); // Independently owned synthetic fixture only.
        store.Save(1, Op(), "localPending", () => true);
        using var later = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require((await later.FirstUseMode!.RecoverLocalAsync(2, Op())).State == "recoveryRequired" && f.Vault.LoadActiveAccountKey() == Account,
            "old exact checkpoint cannot acknowledge a later pending operation");
    }

    private static async Task GuardsAndBinding()
    {
        using (var f = new Fixture())
        {
            await f.CreateAccount(); var store = new FirstUseModeStore(f.Root); var pending = store.Save(0, Op(), "localPending", () => true);
            var stamp = f.Vault.CaptureRetirement(Account);
            foreach (var partial in new[] {
                new LocalAccountStopObservation("publicationPending", f.Host!.Generation, true, false, true, true),
                new LocalAccountStopObservation("credentialClearPending", f.Host.Generation, true, true, false, true),
                new LocalAccountStopObservation("credentialClearPending", f.Host.Generation, false, true, true, true),
                new LocalAccountStopObservation("credentialClearPending", f.Host.Generation, true, true, true, false) })
                await Expect("firstUse.mode_receipt_required", () => Task.Run(() => store.SaveCredentialCheckpoint(pending, partial, stamp, () => true)));
            Require(!File.Exists(CheckpointPath(f.Root)), "none of the missing real exit facts creates partial cleanup authority");
            var stopped = await f.Runtime!.StopAccountForLocalModeAsync(f.Host!.Generation, default, (facts, credential, current) => {
                var reads = 0;
                store.SaveCredentialCheckpoint(pending, facts, credential, () => current() && ++reads < 2);
            });
            Require(stopped.State == "unavailable" && !File.Exists(CheckpointPath(f.Root)) && f.Vault.LoadActiveAccountKey() == Account,
                "late checkpoint guard failure keeps credential intact and cannot publish a checkpoint");
        }
        using (var f = new Fixture())
        {
            await Child(f, "wrongPath");
            var bytes = File.ReadAllBytes(Path.Combine(f.Root, "custom-vault.json"));
            using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
            Require((await cold.FirstUseMode!.RecoverLocalAsync(1, Op())).State == "recoveryRequired" &&
                bytes.SequenceEqual(File.ReadAllBytes(Path.Combine(f.Root, "custom-vault.json"))), "unknown vault target is not chosen from caller data or guessed");
        }
    }

    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-credential-checkpoint", Guid.NewGuid().ToString("N"));
        private string _vaultFileName = "scm-token-vault.json";
        internal string VaultPath => Path.Combine(Root, _vaultFileName);
        internal WindowsTokenVault Vault => new(VaultPath);
        internal Transport Transport { get; } = new();
        internal ScmAccountBridgeHost? Host;
        internal AccountBridgeRuntime? Runtime;
        internal LocalPrivacyStore? Privacy;
        private readonly string _previousRoot;
        private readonly bool _preserve;
        internal Fixture(string? root = null, bool preserve = false)
        {
            if (root is not null) Root = Path.GetFullPath(root);
            _preserve = preserve; CheckRoot(); Directory.CreateDirectory(Root);
            _previousRoot = HostDataRoot.CurrentRoot; HostDataRoot.UsePreparedRoot(Root);
        }
        internal async Task CreateAccount(bool customPath = false, bool publication = false, string? fileName = null)
        {
            _vaultFileName = fileName ?? (customPath ? "custom-vault.json" : "scm-token-vault.json");
            var vault = new WindowsTokenVault(VaultPath);
            vault.SaveRefreshToken(Account, "synthetic-initial-refresh");
            var endpoint = new Uri("https://auth.example.invalid/");
            var options = new ScmOAuthOptions("synthetic-checkpoint", endpoint, endpoint, endpoint, "synthetic-client", "synthetic-resource", "profile.read presence.write", "/callback");
            var oauth = new OAuthPkceClient(new ScmHttpClient(Transport), vault, options);
            var session = (await oauth.TryRestoreSessionAsync(default))!;
            Host = new(oauth, new ScmProfileCacheStore(Path.Combine(Root, "profile")), "synthetic-environment", () => null, initialSession: session);
            Privacy = publication ? new LocalPrivacyStore(Root) : null;
            Runtime = new(Host, privacy: Privacy);
            await AccountBridgeRuntime.CreateWithFirstUseModeAsync(Root, _ => Task.FromResult(Runtime));
        }
        public void Dispose()
        {
            Runtime?.Dispose(); Transport.Dispose(); HostDataRoot.UsePreparedRoot(_previousRoot);
            if (!_preserve) { CheckRoot(); Directory.Delete(Root, recursive: true); }
        }
        private void CheckRoot()
        {
            var expected = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-credential-checkpoint"));
            if (Path.GetDirectoryName(Root) != expected || !Guid.TryParseExact(Path.GetFileName(Root), "N", out _)) throw new InvalidOperationException("Unsafe fixture target");
            for (var node = Root; node is not null; node = Path.GetDirectoryName(node))
            {
                FileAttributes attributes;
                try { attributes = File.GetAttributes(node); } catch (FileNotFoundException) { continue; } catch (DirectoryNotFoundException) { continue; }
                if (attributes.HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture target");
            }
        }
    }
    private sealed class Transport : HttpMessageHandler
    {
        internal int Requests;
        internal Action? Revoke;
        internal bool WithdrawalAllowed;
        internal int Withdrawals;
        internal Action? BeforeWithdrawal;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested(); Requests++;
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/players/realtime" && WithdrawalAllowed)
            {
                using var document = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Require(!document.RootElement.GetProperty("online").GetBoolean(), "synthetic transport accepts only actual withdrawal");
                BeforeWithdrawal?.Invoke(); Withdrawals++;
                var reply = new HttpResponseMessage(HttpStatusCode.OK) { Content = System.Net.Http.Json.JsonContent.Create(document.RootElement.Clone()) };
                reply.Headers.Add("X-StarBridge-Realtime-Version", "1");
                return reply;
            }
            string body;
            if (path.EndsWith("/token", StringComparison.Ordinal)) body = "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-refresh\",\"token_type\":\"Bearer\",\"expires_in\":3600}";
            else if (path.EndsWith("/revoke", StringComparison.Ordinal)) { Revoke?.Invoke(); body = "{}"; }
            else if (path.EndsWith("/me", StringComparison.Ordinal)) body = "{\"subject\":\"synthetic-pilot\",\"displayName\":\"Synthetic Pilot\",\"capabilities\":[\"profile.read\",\"presence.write\"],\"gameIdentity\":{\"status\":\"verified\",\"handle\":\"Pilot-Example\",\"normalizedHandle\":\"pilot-example\",\"verified\":true}}";
            else throw new InvalidOperationException("Unexpected synthetic OAuth request");
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        }
    }
}

