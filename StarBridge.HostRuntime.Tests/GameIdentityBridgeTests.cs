using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class GameIdentityBridgeTests
{
    // Every value and transport in this fixture is synthetic and memory-only.
    private const string Handle = "Fixture_Idv_Pilot";
    private const string Contact = "fixture-idv-contact";
    private const string Code = "fixture-idv-code";
    private const string Message = "fixture-idv-private-rejection";
    private const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    private static int _assertions;

    internal static async Task Run()
    {
        _assertions = 0;
        var groups = new (string Name, Func<Task> Run)[]
        {
            ("code outcomes", CodeOutcomes),
            ("nullable and invalid code expiry", CodeExpiry),
            ("verify outcomes and authoritative projection", VerifyOutcomes),
            ("identity notification preserves menu hotkey lease", MenuLease),
            ("ambiguous write reconciliation", Reconciliation),
            ("strict payload and context validation", Validation),
            ("fixed profile opener", ProfileOpener),
            ("single-flight, prompt reads and account retirement", Concurrency),
            ("same account replacement and late refresh", AccountReplacement),
            ("already verified and identity policy mapping", IdentityStates),
            ("participant enrollment states and first POST", Enrollment),
            ("post-refresh participant identity check", EnrollmentRefresh),
            ("verification wakes the running enrollment loop", EnrollmentWake),
            ("committed refresh survives resource failure and cancellation", TokenRefresh),
            ("installed SCM capability handshake", Capabilities),
            ("private diagnostics", Diagnostics)
        };
        var failures = 0;
        foreach (var (name, run) in groups)
        {
            try { await run(); Console.WriteLine("PASS game identity " + name); }
            catch (Exception error) { failures++; Console.WriteLine("FAIL game identity " + name + ": " +
                (error is AssertionFailure ? error.Message : error.GetType().Name)); }
        }
        Console.WriteLine($"SUMMARY game identity passed={groups.Length - failures} failed={failures} assertions={_assertions}");
        if (failures != 0) throw new InvalidOperationException("Game identity regression failed.");
    }

    private static async Task CodeOutcomes()
    {
        using var f = new Fixture();
        var issued = await f.Send(GameIdentityBridge.RequestCode);
        Outcome(issued, "issued");
        Check(issued.Response.Payload.GetProperty("verificationCode").GetString() == Code &&
            issued.Response.Payload.GetProperty("expiresInSeconds").GetInt64() == 120, "code response fields");
        f.Wire.Mode = "rejected";
        var rejected = await f.Send(GameIdentityBridge.RequestCode);
        Outcome(rejected, "rejected");
        Check(rejected.Response.Payload.GetProperty("message").GetString() == Message, "SCM rejection retained");
        f.Wire.Message = new string('x', 700);
        Check((await f.Send(GameIdentityBridge.RequestCode)).Response.Payload.GetProperty("message").GetString()!.Length == 512,
            "message bounded");
        f.Wire.Message = null;
        Check((await f.Send(GameIdentityBridge.RequestCode)).Response.Payload.GetProperty("message").ValueKind == JsonValueKind.Null,
            "null rejection message");
        f.Wire.Mode = "http-rejected";
        Outcome(await f.Send(GameIdentityBridge.RequestCode), "rejected");
        foreach (var mode in new[] { "forbidden", "business-forbidden", "timeout", "network", "bad-gateway", "unavailable" })
        {
            f.Wire.Mode = mode;
            Outcome(await f.Send(GameIdentityBridge.RequestCode), mode.Contains("forbidden") ? "reauthorizationRequired" : "unavailable");
        }
        using var noScope = new Fixture(scopes: []);
        Outcome(await noScope.Send(GameIdentityBridge.RequestCode), "reauthorizationRequired");
        Check(noScope.Wire.Calls == 0, "missing scope sends nothing");
    }

    private static async Task VerifyOutcomes()
    {
        using var f = new Fixture();
        var generation = f.Host.Generation;
        var accountChanges = 0;
        f.Host.AccountChanged += _ => accountChanges++;
        var verified = await f.Send(GameIdentityBridge.Verify);
        Outcome(verified, "verified");
        Check(verified.Response.Payload.GetProperty("authoritativeHandle").GetString() == Handle,
            "response comes from SCM authoritative handle");
        Check(verified.Events.Single().Name == "gameIdentity.changed" && verified.Events[0].SessionGeneration == generation,
            "identity invalidation uses domain event and current generation");
        Check(accountChanges == 0 && f.Host.Generation == generation, "identity verification does not invalidate the account");
        var policy = await f.Host.GetGameIdentityPolicyAsync(f.Owner, default);
        Check(policy.State == "match" && policy.SensitiveWritesAllowed && f.Session.GameIdentityVerified,
            "refreshed authoritative session installed");
        Check((await f.Host.GetCurrentAsync(default)).State == "signedIn", "account current remains available");
        foreach (var mode in new[] { "rejected", "http-rejected", "forbidden", "business-forbidden", "unavailable" })
        {
            using var failed = new Fixture();
            failed.Wire.Mode = mode;
            var result = await failed.Send(GameIdentityBridge.Verify);
            Outcome(result, mode.EndsWith("rejected", StringComparison.Ordinal) ? "rejected" : mode == "unavailable" ? "outcomeUnknown" : "reauthorizationRequired");
            Check(!failed.Session.GameIdentityVerified && result.Events.Count == 0, "no success state on rejection");
            if (mode.Contains("forbidden")) Check(failed.Wire.MeReads == 0, "403 cannot trigger reconciliation");
        }
        using var noScope = new Fixture(scopes: []);
        Outcome(await noScope.Send(GameIdentityBridge.Verify), "reauthorizationRequired");
        Check(noScope.Wire.Calls == 0, "verify missing scope sends nothing");
    }

    private static async Task CodeExpiry()
    {
        using var f = new Fixture();
        f.Wire.Mode = "rejected";
        f.Wire.ExpireTime = null;
        f.Wire.VerificationCode = null;
        var rejected = await f.Send(GameIdentityBridge.RequestCode);
        Outcome(rejected, "rejected");
        Check(rejected.Response.Payload.GetProperty("message").GetString() == Message,
            "HTTP 200 rejection with null code and expiry retains SCM message");
        f.Wire.Mode = "ok";
        f.Wire.VerificationCode = Code;
        foreach (var expiry in new long?[] { null, 0, -1 })
        {
            f.Wire.ExpireTime = expiry;
            var invalid = await f.Send(GameIdentityBridge.RequestCode);
            Outcome(invalid, "unavailable");
            Check(!invalid.Response.Payload.TryGetProperty("verificationCode", out _), "invalid expiry never exposes issued code");
        }
        f.Wire.ExpireTime = 120;
        f.Wire.VerificationCode = null;
        Outcome(await f.Send(GameIdentityBridge.RequestCode), "unavailable");
    }

    private static async Task MenuLease()
    {
        using var f = new Fixture();
        var native = new MenuRuntime();
        using var menu = new MenuHotkeyBridgeDispatcher(native, () => ("fixture-owner", f.Host.Generation),
            f.Runtime.MenuHotkeyIntent, 42);
        f.Runtime.ConfigureMenuHotkeys(menu);
        var intents = new List<BridgeEnvelope>();
        menu.EventReady += intents.Add;
        var attached = await menu.DispatchAsync(BridgeEnvelope.Request("menuHotkey.attach", "fixture-menu-attach", f.Host.Generation,
            new { schemaVersion = 1, client = 1, binding = "Alt+M", enabled = true, closeWithHotkey = true }));
        Check(attached.Response.Status == "ok", "menu lease attached before verification");
        var lease = native.Registration!;
        Check(lease.IsCurrent(), "menu lease initially current");
        var capabilities = f.Runtime.AdditionalHostCapabilities.ToArray();
        var notifications = 0;
        var gateReleased = false;
        var stateCommitted = false;
        var operationCompleted = false;
        typeof(ScmAccountBridgeHost).GetField("_participationNextCheck", Private)!.SetValue(f.Host, DateTimeOffset.UtcNow.AddMinutes(1));
        f.Host.GameIdentityChanged += generation =>
        {
            notifications++;
            var gate = (AccountMutationGate)typeof(ScmAccountBridgeHost).GetField("_mutationGate", Private)!.GetValue(f.Host)!;
            gateReleased = gate.WaitAsync(TimeSpan.Zero, default).GetAwaiter().GetResult();
            if (gateReleased) gate.Release();
            stateCommitted = generation == f.Host.Generation && f.Session.GameIdentityVerified;
            operationCompleted = (DateTimeOffset)typeof(ScmAccountBridgeHost).GetField("_participationNextCheck", Private)!.GetValue(f.Host)! == default &&
                typeof(ScmAccountBridgeHost).GetField("_gameIdentityOperation", Private)!.GetValue(f.Host) is null;
        };
        Outcome(await f.Send(GameIdentityBridge.Verify), "verified");
        Check(notifications == 1, "one identity change notification after verification");
        Check(gateReleased, "identity notification runs outside mutation gate");
        Check(stateCommitted, "identity notification observes committed state in same generation");
        Check(operationCompleted, "identity notification observes reset participation check and completed operation");
        Check(ReferenceEquals(native.Registration, lease) && lease.IsCurrent(), "verification retains original menu lease without reattach");
        lease.Trigger(new("open", 0, 44, 66));
        Check(intents.Count == 1 && intents[0].Name == "menuHotkey.intent", "Alt+M intent still delivered after verification");
        Check(capabilities.SequenceEqual(f.Runtime.AdditionalHostCapabilities), "installed SCM capabilities unchanged");
    }

    private sealed class MenuRuntime : IMenuHotkeyRuntime
    {
        internal MenuHotkeyRegistration? Registration;
        public ValueTask<string> ConfigureMenuHotkeyAsync(MenuHotkeyRegistration? registration, CancellationToken cancellationToken = default)
        { Registration = registration; return ValueTask.FromResult("registered"); }
        public ValueTask UpdateMenuWindowAsync(MenuHotkeyRegistration registration, long request, string phase, long window,
            CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
    }

    private static async Task Reconciliation()
    {
        foreach (var mode in new[] { "timeout", "network", "bad-gateway" })
        {
            using var reconciled = new Fixture();
            reconciled.Wire.Mode = mode;
            reconciled.Wire.CommitAmbiguous = true;
            Outcome(await reconciled.Send(GameIdentityBridge.Verify), "verified");
            Check(reconciled.Wire.Verifies == 1 && reconciled.Wire.MeReads == 1 && reconciled.Session.GameIdentityVerified,
                "ambiguous commit read once, never replayed");
            using var unknown = new Fixture();
            unknown.Wire.Mode = mode;
            unknown.Wire.ReadFails = true;
            Outcome(await unknown.Send(GameIdentityBridge.Verify), "outcomeUnknown");
            Check(unknown.Wire.Verifies == 1 && unknown.Wire.MeReads == 1 && !unknown.Session.GameIdentityVerified,
                "failed read cannot claim success or failure");
        }
        using var notCommitted = new Fixture();
        notCommitted.Wire.Mode = "timeout";
        Outcome(await notCommitted.Send(GameIdentityBridge.Verify), "outcomeUnknown");
        using var acknowledged = new Fixture();
        acknowledged.Wire.ReadFails = true;
        Outcome(await acknowledged.Send(GameIdentityBridge.Verify), "outcomeUnknown");
    }

    private static async Task Validation()
    {
        using var f = new Fixture();
        var invalid = new (string Command, object Payload)[]
        {
            (GameIdentityBridge.RequestCode, new { schemaVersion = 1, gameName = "ab" }),
            (GameIdentityBridge.RequestCode, new { schemaVersion = 1, gameName = "bad handle" }),
            (GameIdentityBridge.RequestCode, new { schemaVersion = 1, gameName = Handle, extra = true }),
            (GameIdentityBridge.RequestCode, new { schemaVersion = 1 }),
            (GameIdentityBridge.RequestCode, new { schemaVersion = "1", gameName = Handle }),
            (GameIdentityBridge.RequestCode, new { schemaVersion = 1, gameName = 123 }),
            (GameIdentityBridge.Verify, new { schemaVersion = 1, gameName = Handle, contact = "short" }),
            (GameIdentityBridge.Verify, new { schemaVersion = 1, gameName = Handle, contact = new string('x', 257) }),
            (GameIdentityBridge.Verify, new { schemaVersion = 1, gameName = Handle, contact = (string?)null }),
            (GameIdentityBridge.Verify, new { schemaVersion = 1, gameName = Handle }),
            (GameIdentityBridge.Verify, new { schemaVersion = 1, gameName = Handle, contact = Contact, extra = true }),
            (GameIdentityBridge.OpenProfile, new { schemaVersion = 1, url = "https://example.invalid/" }),
            (GameIdentityBridge.OpenProfile, new { schemaVersion = 2 }),
            (GameIdentityBridge.OpenProfile, new { })
        };
        foreach (var (command, payload) in invalid)
            Check((await f.Send(command, payload)).Response.Error is not null, "invalid payload rejected");
        using var duplicate = JsonDocument.Parse("{\"schemaVersion\":1,\"gameName\":\"abc\",\"gameName\":\"def\"}");
        Check((await f.Send(GameIdentityBridge.RequestCode, duplicate.RootElement)).Response.Error is not null, "duplicate key rejected");
        foreach (var command in new[] { GameIdentityBridge.RequestCode, GameIdentityBridge.Verify, GameIdentityBridge.OpenProfile })
        {
            Check((await f.Send(command, context: f.Owner with { Subject = "other" })).Response.Error?.Code == BridgeErrorCodes.AccountContextRequired,
                "wrong context uses existing account error");
            Check((await f.Send(command, generation: 99)).Response.Error?.Code == BridgeErrorCodes.StaleGeneration,
                "stale generation rejected");
            var absent = await f.Runtime.DispatchAsync(BridgeEnvelope.Request(command, Guid.NewGuid().ToString("N"),
                f.Host.Generation, Payload(command)));
            Check(absent.Response.Error is not null, "all commands require context");
        }
        Check(f.Wire.Calls == 0 && f.Opened.Count == 0, "invalid payload cannot send or open");
        Outcome(await f.Send(GameIdentityBridge.RequestCode, new { schemaVersion = 1, gameName = "  " + Handle + "  " }), "issued");
        Outcome(await f.Send(GameIdentityBridge.Verify, new { schemaVersion = 1, gameName = " " + Handle, contact = Contact + "  " }), "verified");
    }

    private static async Task ProfileOpener()
    {
        using var f = new Fixture(scopes: []);
        var opened = await f.Send(GameIdentityBridge.OpenProfile);
        Check(opened.Response.Payload.GetProperty("opened").GetBoolean() && f.Opened.Single().AbsoluteUri ==
            "https://robertsspaceindustries.com/account/profile", "only fixed profile address opened through substitute");
        f.OpenFails = true;
        Check(!(await f.Send(GameIdentityBridge.OpenProfile)).Response.Payload.GetProperty("opened").GetBoolean(), "browser failure is false");
        Check(f.Wire.Calls == 0, "profile open never accesses HTTP");
    }

    private static async Task Concurrency()
    {
        foreach (var command in new[] { GameIdentityBridge.RequestCode, GameIdentityBridge.Verify })
        {
            using var f = new Fixture();
            f.Wire.Hold = true;
            var pending = f.Send(command);
            await f.Wire.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var busy = await f.Send(GameIdentityBridge.Verify).WaitAsync(TimeSpan.FromSeconds(2));
            Check(busy.Response.Error?.Code == AccountBridgeStableErrors.OperationInProgress, "second operation promptly busy");
            var current = await f.Runtime.DispatchAsync(BridgeEnvelope.Request(AccountBridgeRequestNames.GetCurrent,
                "current", f.Host.Generation, new { schemaVersion = 1 })).AsTask().WaitAsync(TimeSpan.FromSeconds(2));
            Check(current.Response.Error is null, "account read does not wait for verification IO");
            await f.Host.LogoutAsync(f.Owner, default).WaitAsync(TimeSpan.FromSeconds(2));
            f.Wire.Release.TrySetResult();
            var stale = await pending.WaitAsync(TimeSpan.FromSeconds(3));
            Check(stale.Response.Error is not null && f.Host.CurrentContext is null && f.SessionOrNull is null,
                "logout during IO cannot restore result");
        }
    }

    private static async Task AccountReplacement()
    {
        using var f = new Fixture();
        f.Wire.Hold = true;
        var pending = f.Send(GameIdentityBridge.Verify);
        await f.Wire.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var replacement = f.Session with { Subject = "other-owner" };
        Publish(f.Host, replacement);
        f.Wire.Release.TrySetResult();
        Check((await pending).Response.Error is not null && ReferenceEquals(f.Session, replacement), "different account never overwritten");
        using var same = new Fixture();
        same.Wire.Hold = true;
        var old = same.Send(GameIdentityBridge.Verify);
        await same.Wire.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var renewed = same.Session with { DisplayName = "new login" };
        Publish(same.Host, renewed);
        same.Wire.Release.TrySetResult();
        Check((await old).Response.Error is not null && ReferenceEquals(same.Session, renewed), "same subject new generation never overwritten");
        using var disposed = new Fixture();
        disposed.Wire.Hold = true;
        var retiring = disposed.Send(GameIdentityBridge.Verify);
        await disposed.Wire.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        disposed.Host.Dispose();
        disposed.Wire.Release.TrySetResult();
        Check((await retiring).Response.Error is not null && !disposed.Session.GameIdentityVerified, "disposed host never accepts late result");
    }

    private static async Task IdentityStates()
    {
        foreach (var (status, expected) in new[] { (ScmGameIdentityStatus.Unverified, "verificationRequired"),
            (ScmGameIdentityStatus.Pending, "verificationPending") })
        {
            using var f = new Fixture(status);
            var projection = await f.Host.GetGameIdentityPolicyAsync(f.Owner, default);
            Check(projection.State == expected && !projection.SensitiveWritesAllowed, "unverified policy is read only");
        }
        using var verified = new Fixture(ScmGameIdentityStatus.Verified);
        Outcome(await verified.Send(GameIdentityBridge.RequestCode), "alreadyVerified");
        Outcome(await verified.Send(GameIdentityBridge.Verify), "alreadyVerified");
        Check(verified.Wire.Calls == 0, "verified session sends no verification requests");
    }

    private static async Task Enrollment()
    {
        foreach (var status in new[] { ScmGameIdentityStatus.Unverified, ScmGameIdentityStatus.Pending })
        {
            using var f = new Fixture(status);
            await Enroll(f);
            Check(f.Wire.Posts == 0 && f.Wire.Puts == 0 && f.Wire.BusinessReads == 0, "unverified enrollment entirely skipped");
            f.Clock.Now += TimeSpan.FromMinutes(1);
            await Enroll(f);
            Check(f.Wire.Posts == 0 && f.Wire.Puts == 0, "unverified retry sends no writes");
            Outcome(await f.Send(GameIdentityBridge.Verify), "verified");
            await Enroll(f);
            Check(f.Wire.Posts == 1 && f.Wire.Puts == 0, "verification resets check and preserves first POST");
            f.Clock.Now += TimeSpan.FromMinutes(1);
            await Enroll(f);
            Check(f.Wire.Posts == 1 && f.Wire.Puts == 1, "following enrollment uses PUT");
        }
        foreach (var status in new[] { ScmGameIdentityStatus.Revoked, ScmGameIdentityStatus.ReverifyRequired,
            ScmGameIdentityStatus.Verified, ScmGameIdentityStatus.Unknown })
        {
            using var f = new Fixture(status);
            await Enroll(f);
            f.Clock.Now += TimeSpan.FromMinutes(1);
            await Enroll(f);
            Check(f.Wire.Posts == 1 && f.Wire.Puts == 1, "existing non-unverified enrollment preserved");
        }
        using var cancelled = new Fixture();
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        try { await Enroll(cancelled, cancellation.Token); Check(false, "cancel must propagate"); }
        catch (OperationCanceledException) { Check(true, "unverified branch cannot swallow cancellation"); }
    }

    private static async Task EnrollmentWake()
    {
        using var f = new Fixture(ScmGameIdentityStatus.Unverified);
        f.Host.EnableParticipantSynchronization(TimeSpan.FromHours(1));
        // Let the first round finish so the loop is inside its long wait.
        await Task.Delay(300);
        Check(f.Wire.Posts == 0, "the unverified round registers nothing");
        Outcome(await f.Send(GameIdentityBridge.Verify), "verified");
        for (var i = 0; i < 250 && f.Wire.Posts == 0; i++) await Task.Delay(20);
        Check(f.Wire.Posts == 1 && f.Wire.Puts == 0, "verification registers now, not at the next interval");
    }

    private static async Task EnrollmentRefresh()
    {
        foreach (var status in new[] { ScmGameIdentityStatus.Unverified, ScmGameIdentityStatus.Pending })
        {
            using var f = new Fixture(ScmGameIdentityStatus.Unknown, expires: DateTimeOffset.UtcNow.AddMinutes(-1));
            f.Wire.IdentityStatus = status;
            await Enroll(f);
            Check(f.Wire.BusinessReads == 1 && f.Wire.Refreshes == 1 && f.Wire.Posts == 0 && f.Wire.Puts == 0,
                "business identity active session rechecked after refresh");
            Check((long)typeof(ScmAccountBridgeHost).GetField("_participationAttemptGeneration", Private)!.GetValue(f.Host)! == -1,
                "skipped refresh cannot consume registration attempt");
        }
    }

    private static async Task TokenRefresh()
    {
        foreach (var command in new[] { GameIdentityBridge.RequestCode, GameIdentityBridge.Verify })
        foreach (var mode in new[] { "bad-gateway", "timeout", "cancel" })
        {
            using var f = new Fixture(expires: DateTimeOffset.UtcNow.AddMinutes(-1));
            using var cancellation = new CancellationTokenSource();
            f.Wire.Mode = mode;
            f.Wire.ReadFailsAfterRefresh = true;
            f.Wire.OnResource = mode == "cancel" ? cancellation.Cancel : null;
            var old = f.Session;
            var result = await f.Send(command, token: cancellation.Token);
            if (mode == "cancel") Check(result.Response.Status == "cancelled", "caller cancellation preserved");
            else Outcome(result, command == GameIdentityBridge.Verify ? "outcomeUnknown" : "unavailable");
            Check(f.Wire.Refreshes == 1 && f.Vault.Saves == 1 && f.Session.CredentialVersion != old.CredentialVersion &&
                f.Session.ExpiresAt > old.ExpiresAt, "Host adopts persisted refresh before failed IO");
        }
        foreach (var command in new[] { GameIdentityBridge.RequestCode, GameIdentityBridge.Verify })
        {
            using var unauthorized = new Fixture();
            var before = unauthorized.Session;
            unauthorized.Wire.Mode = "unauthorized-then-fail";
            unauthorized.Wire.ReadFailsAfterRefresh = true;
            Outcome(await unauthorized.Send(command), command == GameIdentityBridge.Verify ? "outcomeUnknown" : "unavailable");
            Check(unauthorized.Wire.Refreshes == 1 && unauthorized.Vault.Saves == 1 &&
                unauthorized.Session.CredentialVersion != before.CredentialVersion, "401 refresh survives replay failure");
            using var removedScope = new Fixture(expires: DateTimeOffset.UtcNow.AddMinutes(-1));
            removedScope.Wire.IdentityScopes = ["profile.read"];
            Outcome(await removedScope.Send(command), "reauthorizationRequired");
            Check(removedScope.Wire.Codes == 0 && removedScope.Wire.Verifies == 0 && removedScope.Vault.Saves == 1,
                "refreshed permission checked before sending private payload");
        }
    }

    private static async Task Capabilities()
    {
        using var f = new Fixture();
        var handshake = new HostBridgeDispatcher("fixture", () => f.Host.Generation, ["host.lifecycle"],
            additionalCapabilities: () => f.Runtime.AdditionalHostCapabilities);
        var ready = await handshake.DispatchAsync(BridgeEnvelope.Request("host.hello", "hello", f.Host.Generation,
            new { protocols = new { minimum = 1, maximum = 1 }, capabilities = Array.Empty<string>() }));
        Check(f.Runtime.AdditionalHostCapabilities.Contains(GameIdentityBridge.Capability), "installed SCM declares capability");
        Check(!f.Runtime.OfficialFleetRealtimeCapabilities.Contains(GameIdentityBridge.Capability), "fleet protocol list stays separate");
        Check(ready.Response.Error is null && ready.Response.Payload.GetRawText().Contains(GameIdentityBridge.Capability), "handshake permits dynamic capability");
        await f.Host.LogoutAsync(f.Owner, default);
        Check(!f.Runtime.AdditionalHostCapabilities.Contains(GameIdentityBridge.Capability), "logged out capability withdrawn");
        using var noSession = new Fixture(empty: true);
        Check(!noSession.Runtime.AdditionalHostCapabilities.Contains(GameIdentityBridge.Capability), "absent session no capability");
        Check(!AccountBridgeRuntime.AdvertisedCapabilities.Contains(GameIdentityBridge.Capability), "capability never globally advertised");
        typeof(ScmAccountBridgeHost).GetField("_legacySession", Private)!.SetValue(noSession.Host,
            new LegacyMigrationCredential("legacy-fixture", null, "synthetic-legacy", DateTimeOffset.UtcNow));
        Check(!noSession.Runtime.AdditionalHostCapabilities.Contains(GameIdentityBridge.Capability), "legacy session cannot declare SCM verification");
    }

    private static async Task Diagnostics()
    {
        foreach (var mode in new[] { "network", "timeout", "forbidden", "bad-gateway", "malformed" })
        {
            using var f = new Fixture();
            f.Wire.Mode = mode;
            try
            {
                await f.OAuth.GetGameIdentityVerificationCodeAsync(f.Session, Handle, default);
                Check(false, "transport must fail in exception privacy fixture");
            }
            catch (Exception error) when (error is HttpRequestException or OperationCanceledException or ScmApiProtocolException)
            {
                foreach (var value in new[] { Handle, Contact, Code, Message })
                    Check(!error.Message.Contains(value, StringComparison.Ordinal), "exception excludes private response data");
                Check(error.InnerException is null, "exception cannot retain private inner failure");
            }
        }
        var root = HostDataRoot.CurrentRoot;
        var files = Directory.Exists(root) ? Directory.GetFiles(root, "*.log", SearchOption.AllDirectories) : [];
        Check(files.Length > 0, "exercise real diagnostic writes");
        foreach (var path in files)
        {
            var log = File.ReadAllText(path);
            foreach (var value in new[] { Handle, Handle.ToLowerInvariant(), Contact, Code, Message })
                Check(!log.Contains(value, StringComparison.Ordinal), "diagnostics exclude private fixture values");
        }
    }

    private static Task Enroll(Fixture f, CancellationToken token = default) =>
        (Task)typeof(ScmAccountBridgeHost).GetMethod("EnsureParticipantEnrollmentAsync", Private)!.Invoke(f.Host, [token, false])!;
    private static void Publish(ScmAccountBridgeHost host, ScmOAuthSession session) =>
        typeof(ScmAccountBridgeHost).GetMethod("PublishSession", Private)!.Invoke(host, [session, false, null, false, null, null, null, null]);
    private static object Payload(string command) => command switch
    {
        GameIdentityBridge.RequestCode => new { schemaVersion = 1, gameName = Handle },
        GameIdentityBridge.Verify => new { schemaVersion = 1, gameName = Handle, contact = Contact },
        _ => new { schemaVersion = 1 }
    };
    private static void Outcome(BridgeDispatchBatch result, string expected) =>
        Check(result.Response.Error is null && result.Response.Payload.TryGetProperty("outcome", out var outcome) &&
            outcome.GetString() == expected, "expected outcome " + expected);
    private static void Check(bool condition, string description)
    {
        _assertions++;
        if (!condition) throw new AssertionFailure(description);
    }
    private sealed class AssertionFailure(string description) : Exception(description);

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Vault : ITokenVault
    {
        internal int Saves;
        public void SaveRefreshToken(string key, string value) { Saves++; }
        public string? LoadRefreshToken(string key) => "synthetic-refresh";
        public string? LoadActiveAccountKey() => "synthetic:owner";
        public void DeleteRefreshToken(string key) { }
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly Wire Wire = new();
        internal readonly Vault Vault = new();
        internal readonly Clock Clock = new();
        internal readonly OAuthPkceClient OAuth;
        internal readonly ScmAccountBridgeHost Host;
        internal readonly AccountBridgeRuntime Runtime;
        internal readonly List<Uri> Opened = [];
        internal bool OpenFails;
        internal BridgeAccountContext Owner => new("integration", "synthetic", "owner");
        internal ScmOAuthSession? SessionOrNull => (ScmOAuthSession?)typeof(ScmAccountBridgeHost).GetField("_session", Private)!.GetValue(Host);
        internal ScmOAuthSession Session => SessionOrNull!;
        internal Fixture(ScmGameIdentityStatus status = ScmGameIdentityStatus.Unverified, string[]? scopes = null,
            DateTimeOffset? expires = null, bool empty = false)
        {
            Wire.IdentityStatus = status;
            var uri = new Uri("http://127.0.0.1:9/");
            OAuth = new OAuthPkceClient(new ScmHttpClient(Wire), Vault,
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read game_identity.verify", "/callback"),
                authorizationBrowser: address => { if (OpenFails) throw new InvalidOperationException("synthetic browser failure"); Opened.Add(address); });
            var session = empty ? null : new ScmOAuthSession("synthetic", "owner", "Fixture", "synthetic-read",
                expires ?? DateTimeOffset.UtcNow.AddHours(1), scopes ?? ["profile.read", "game_identity.verify"],
                GameIdentityVerified: status == ScmGameIdentityStatus.Verified,
                GameIdentityHandle: status == ScmGameIdentityStatus.Verified ? Handle : null, GameIdentityStatus: status);
            Host = new(OAuth, new ScmProfileCacheStore(), "integration", () => null, initialSession: session) { ParticipantClock = Clock };
            Runtime = new(Host);
        }
        internal Task<BridgeDispatchBatch> Send(string command, object? payload = null, BridgeAccountContext? context = null,
            long? generation = null, CancellationToken token = default) => Runtime.DispatchAsync(BridgeEnvelope.Request(
                command, Guid.NewGuid().ToString("N"), generation ?? Host.Generation, payload ?? Payload(command), context ?? Owner), token).AsTask();
        public void Dispose() { Wire.Release.TrySetResult(); Runtime.Dispose(); Wire.Dispose(); }
    }

    private sealed class Wire : HttpMessageHandler
    {
        internal string Mode = "ok";
        internal string? Message = GameIdentityBridgeTests.Message;
        internal long? ExpireTime = 120;
        internal string? VerificationCode = Code;
        internal ScmGameIdentityStatus IdentityStatus;
        internal string[] IdentityScopes = ["profile.read", "game_identity.verify"];
        internal bool ReadFails, ReadFailsAfterRefresh, CommitAmbiguous, Hold;
        internal int Calls, Codes, Verifies, MeReads, Refreshes, BusinessReads, Posts, Puts;
        internal Action? OnResource;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private static readonly string BusinessId = "scm-v1:" + new string('a', 64);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.RequestUri!.Host == "127.0.0.1", "fixture never reaches external hosts");
            var path = request.RequestUri.AbsolutePath;
            if (path == "/open-api/oauth2/token")
            {
                Refreshes++;
                return Reply(new { access_token = "synthetic-rotated", refresh_token = "synthetic-rotated-refresh", expires_in = 3600, token_type = "Bearer" });
            }
            if (path == "/app-api/starbridge/v1/me")
            {
                MeReads++;
                if (ReadFails || ReadFailsAfterRefresh && MeReads > 1) return new(HttpStatusCode.BadGateway);
                return Reply(new { subject = "owner", displayName = "Fixture", capabilities = IdentityScopes,
                    gameIdentity = new { status = IdentityStatus.ToString() == "ReverifyRequired" ? "REVERIFY_REQUIRED" : IdentityStatus.ToString().ToUpperInvariant(),
                        handle = IdentityStatus == ScmGameIdentityStatus.Verified ? Handle : null,
                        normalizedHandle = IdentityStatus == ScmGameIdentityStatus.Verified ? Handle.ToLowerInvariant() : null,
                        verified = IdentityStatus == ScmGameIdentityStatus.Verified } });
            }
            if (path.Contains("/game-identity/", StringComparison.Ordinal))
            {
                var verify = path.EndsWith("/verify", StringComparison.Ordinal);
                if (verify) Verifies++; else Codes++;
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.GetProperty("gameName").GetString() == Handle, "trimmed game name sent");
                if (verify) Check(body.RootElement.GetProperty("userMobile").GetString() == Contact, "trimmed contact sent");
                Started.TrySetResult();
                if (Hold) await Release.Task.WaitAsync(token);
                OnResource?.Invoke();
                token.ThrowIfCancellationRequested();
                if (Mode == "unauthorized-then-fail")
                {
                    Mode = "bad-gateway";
                    return Reply(new { message = Message }, HttpStatusCode.Unauthorized);
                }
                if (verify && (Mode == "ok" || CommitAmbiguous)) IdentityStatus = ScmGameIdentityStatus.Verified;
                if (Mode == "timeout") throw new TaskCanceledException(Message);
                if (Mode == "network") throw new HttpRequestException(Message);
                if (Mode == "forbidden") return Reply(new { message = Message }, HttpStatusCode.Forbidden);
                if (Mode == "business-forbidden") return Reply(new { code = 403, message = Message });
                if (Mode == "http-rejected") return Reply(new { code = 400, message = Message }, HttpStatusCode.BadRequest);
                if (Mode == "bad-gateway") return Reply(new { message = Message }, HttpStatusCode.BadGateway);
                if (Mode == "malformed") return new(HttpStatusCode.OK) { Content = new StringContent("{invalid:" + Message) };
                return verify ? Reply(new { available = Mode != "unavailable", success = Mode == "ok", message = Message })
                    : Reply(new { available = Mode != "unavailable", success = Mode == "ok", message = Message, verificationCode = VerificationCode, expireTime = ExpireTime });
            }
            if (path == "/app-api/starbridge/v1/business-identity")
            {
                BusinessReads++;
                return Reply(new { schemaVersion = 1, issuer = "synthetic", subject = "owner", businessSubjectId = BusinessId, scopes = new[] { "profile.read" } });
            }
            if (path.StartsWith("/app-api/starbridge/v1/business-identity/registration", StringComparison.Ordinal))
            {
                if (request.Method == HttpMethod.Post) Posts++; else if (request.Method == HttpMethod.Put) Puts++;
                return Reply(new { schemaVersion = 1, businessSubjectId = BusinessId });
            }
            return new(HttpStatusCode.ServiceUnavailable);
        }
        private static HttpResponseMessage Reply(object value, HttpStatusCode status = HttpStatusCode.OK) =>
            new(status) { Content = JsonContent.Create(value) };
    }
}
