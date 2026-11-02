using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    private const BindingFlags RecoveryFields = BindingFlags.Instance | BindingFlags.NonPublic;
    private static OAuthPkceClient OAuth(ScmAccountBridgeHost host) =>
        (OAuthPkceClient)host.GetType().GetField("_oauth", RecoveryFields)!.GetValue(host)!;
    private static ScmOAuthSession HostSession(ScmAccountBridgeHost host) =>
        (ScmOAuthSession)host.GetType().GetField("_session", RecoveryFields)!.GetValue(host)!;

    private sealed class RecoveryRelay : HttpMessageHandler
    {
        internal Func<string?, bool>? Accept;
        internal Action? OnTargets;
        internal int DirectSends;
        internal int GovernanceReads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri?.Host == "recovery.example.invalid", "Injected recovery transport only.");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/privacy/community-scopes")
            {
                OnTargets?.Invoke();
                throw new HttpRequestException("Synthetic resource failure after committed refresh.");
            }
            if (path == "/api/official-fleets/governance/context")
            {
                GovernanceReads++;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    schemaVersion = 1, sourceRef = "officialFleet:7", scopeKey = new string('a', 64), policyRevision = 2,
                    role = "leader",
                    capabilities = new[] { "announcements.manage", "audit.view", "organization.roles.manage" }
                        .Select(capability => new { capability, state = "denied", reason = "notGranted" }),
                    rootAuthority = new { providerState = "observed", controls = new[] { "activate", "recover", "delegate" }
                        .Select(action => new { action, state = "denied", reason = "notGranted" }) }
                }) });
            }
            DirectSends++;
            Check(Accept?.Invoke(request.Headers.Authorization?.Parameter) == true,
                "Direct request must use the actual committed successor bearer.");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = path switch {
                "/api/support/daily" => JsonContent.Create(new { schemaVersion = 1, outcome = "ready", temporaryEntitlements = Array.Empty<object>() }),
                "/api/profile/me/gameplay-time-reset" => JsonContent.Create(new {
                    schemaVersion = 1, revision = 0, playTimeSeconds = 0, historicalPlayTimeSeconds = 0,
                    historicalSessionCount = 0, historicalIncompleteSessionCount = 0, isPublic = false,
                    historyImportOperationId = (string?)null, observedAt = DateTimeOffset.UtcNow }),
                "/api/official-fleets/governance/activation/activate" or
                "/api/official-fleets/governance/activation/revoke" => JsonContent.Create(new {
                    schemaVersion = 1, state = "accepted", operationId = "recovery-intent", policyRevision = 3, auditSequence = 8 }),
                _ => throw new InvalidOperationException("Unexpected direct request.")
            }});
        }
    }

    private static async Task ResourceFailureRecovery()
    {
        var failures = 0;
        foreach (var resource in new[] { "presence", "profile", "community" })
        foreach (var cancel in new[] { false, true })
        foreach (var direct in new[] { "support", "gameplay", "governance-activate", "governance-revoke" })
        {
            try { await ResourceFailureRecovery(resource, cancel, direct); }
            catch (Exception error) { failures++; Console.WriteLine($"FAIL ACHFU recovery {resource}/{cancel}/{direct}: {error.Message}"); }
        }
        Check(failures == 0, "Resource recovery cases failed: " + failures);
    }

    private static async Task PresenceSupersededReceipt()
    {
        foreach (var change in new[] { "refresh", "login", "vault", "identity", "generation", "observation" })
            await PresenceSupersededReceipt(change);
    }

    private static async Task PresenceSupersededReceipt(string change)
    {
        using var f = new Fixture();
        var time = new FirstUseOnlineReturnTests.FrozenSessionTime(); f.Original.SessionTime = time;
        f.Original.Transport.RotateAccessToken = true;
        f.Original.Transport.AllowPresenceWrite = true; f.Original.Transport.AllowProfileRead = true;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Actual original admission required.");
        var host = f.Original.Host!; var owner = host.GameplayTimeContext!; var generation = host.Generation;
        var tokens = f.Original.Transport.TokenRequests; var oauth = OAuth(host);
        var gate = (AccountMutationGate)host.GetType().GetField("_mutationGate", RecoveryFields)!.GetValue(host)!;
        await gate.WaitAsync(default);
        try
        {
            var original = HostSession(host);
            var version = host.GetType().GetField("_realtimeObservationVersion", RecoveryFields)!;
            var before = (long)version.GetValue(host)!;
            time.Now += TimeSpan.FromHours(2);
            // Match the installation fixture's near-expiry token: another real
            // resource read renews it even with a completely frozen clock.
            f.Original.Transport.TokenLifetimeSeconds = 2;
            var receipt = await oauth.UpdatePresenceStatusAsync(original, 1, default);
            f.Original.Transport.TokenLifetimeSeconds = 3600;
            await host.GetProfileAsync(owner, default);
            Check(host.Generation == generation && admission.IsActive && host.GameplayTimeContext == owner &&
                f.Original.Transport.TokenRequests == tokens + 2 && !oauth.IsInstalledFirstUseSessionCurrent(receipt.ActiveSession),
                "Concurrent real profile refresh must retain original owner/generation/admission.");
            if (change == "login") { await oauth.SignInAsync(default); if (f.Original.Callback is { } callback) await Finish(callback); }
            if (change == "vault") f.Original.Vault.SaveRefreshToken("synthetic-scm:synthetic-subject", "synthetic-replacement-refresh");
            if (change == "identity")
            {
                f.Original.Transport.Handle = "Other-Example"; f.Original.Transport.NormalizedHandle = "other-example";
                time.Now += TimeSpan.FromHours(2); await oauth.TryRestoreSessionAsync(default);
            }
            if (change == "generation") generation--;
            if (change == "observation")
            {
                var realtime = host.GetType().GetField("_realtimeGate", RecoveryFields)!.GetValue(host)!;
                lock (realtime) host.GetType().GetMethod("SetRealtimeObservation", RecoveryFields)!.Invoke(host, [null]);
            }
            var sessionBefore = HostSession(host); var observationBefore = version.GetValue(host);
            var rejected = false;
            try
            {
                // This is the exact synchronous production continuation after
                // the await, under its actual mutation lease, with a real PUT
                // receipt. No fabricated session, scheduling wait or test hook.
                var result = host.CommitPresenceVisibilityReceipt(owner, generation, original, receipt, before);
                Check(result == PlayerPresenceVisibilityMode.Online && admission.IsActive,
                    "Real same-owner descendant refresh must not reject a presence success receipt.");
            }
            catch (AccountBridgeHostException error) when (error.Code == "presence.account_changed") { rejected = true; }
            var invalid = change is "login" or "vault" or "identity" or "generation";
            Check(rejected == invalid, "Presence receipt must reject only an unproven replacement/lifecycle: " + change);
            if (invalid) Check(ReferenceEquals(HostSession(host), sessionBefore) && Equals(version.GetValue(host), observationBefore),
                "Rejected receipt must not adopt a replacement or overwrite the presence observation.");
            if (change == "observation") Check(Equals(version.GetValue(host), observationBefore),
                "Later realtime observation/disconnect must still take precedence over the PUT receipt.");
        }
        finally { gate.Release(); }
        await Finish(admission.RetireAsync());
        Console.WriteLine("PASS ACHFU controlled presence receipt with concurrent profile refresh: " + change);
    }

    private static async Task ResourceFailureRecovery(string resource, bool cancel, string direct)
    {
        using var f = new Fixture();
        var time = new FirstUseOnlineReturnTests.FrozenSessionTime(); f.Original.SessionTime = time;
        f.Original.Transport.RotateAccessToken = true;
        using var relay = new RecoveryRelay();
        using var support = new DailySupportClient(new("https://recovery.example.invalid/"), relay);
        f.Original.DailySupport = support;
        f.Original.Legacy = new(new("https://recovery.example.invalid/"), f.Credentials, relay);
        using var communities = new CommunityClient(new("https://recovery.example.invalid/"), relay);
        f.Original.Communities = communities;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Actual original admission required.");
        var host = f.Original.Host!; var owner = host.GameplayTimeContext!; var oauth = OAuth(host);
        var governance = direct.StartsWith("governance-", StringComparison.Ordinal);
        var generation = host.Generation;
        if (governance)
        {
            await host.ReadOfficialFleetGovernanceContextAsync(owner, JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, sourceRef = "officialFleet:7", include = new[] { "role" } }), default);
            Check(relay.GovernanceReads == 1 && host.GovernanceCapabilities.Count == 2,
                "Actual governance context read must establish both mutation capabilities before the resource fault.");
        }
        var original = HostSession(host); var tokens = f.Original.Transport.TokenRequests;
        time.Now += TimeSpan.FromHours(2);
        using var cancellation = new CancellationTokenSource();
        void Fail()
        {
            Check(oauth.ReadInstalledFirstUseRefreshSuccessor(original) is not null,
                "Resource fault must occur after actual OAuth/vault refresh publication.");
            if (cancel) { cancellation.Cancel(); cancellation.Token.ThrowIfCancellationRequested(); }
            throw new HttpRequestException("Synthetic resource failure after committed refresh.");
        }
        f.Original.Transport.BeforeResourceReply = _ => { Fail(); return Task.CompletedTask; };
        f.Original.Transport.AllowPresenceWrite = true; f.Original.Transport.AllowProfileRead = true;
        using var writer = new PrivacyRelayWriter(new("https://recovery.example.invalid/"), relay);
        host.ConfigurePrivacyWriter(writer); relay.OnTargets = Fail;
        var failed = false;
        try
        {
            if (resource == "presence") await host.SetPresenceVisibilityAuthorityAsync(owner, host.Generation, PlayerPresenceVisibilityMode.Online, cancellation.Token);
            else if (resource == "profile") await host.GetProfileAsync(owner, cancellation.Token);
            else await host.ReadCommunitySharingTargetsAsync(owner, host.Generation, cancellation.Token);
        }
        catch (OperationCanceledException) when (cancel && cancellation.IsCancellationRequested) { failed = true; }
        catch (Exception error) when (!cancel && error is HttpRequestException or AccountBridgeHostException) { failed = true; }
        var successor = oauth.ReadInstalledFirstUseRefreshSuccessor(original);
        Check(failed && successor is not null && ReferenceEquals(HostSession(host), original) && admission.IsActive &&
            host.Generation == generation && (!governance || host.GovernanceCapabilities.Count == 2),
            "Failed resource must leave a proven refresh with read-only ownership and no success receipt.");
        relay.Accept = bearer => bearer == successor!.AccessToken;
        // Each case starts independently: no identity review or successful OAuth
        // resource request may hide the stale bearer before this direct path.
        if (direct == "support") await host.DailySupportAsync(owner, BridgePayload.From(new { schemaVersion = 1 }), false, default);
        else if (direct == "gameplay") await host.ReadAsync(owner, default);
        else
        {
            var command = JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, sourceRef = "officialFleet:7", operationId = "recovery-intent", expectedPolicyRevision = 2 });
            var result = (JsonElement)(direct == "governance-activate"
                ? await host.ActivateOfficialFleetGovernanceAsync(owner, command, default)
                : await host.RevokeOfficialFleetGovernanceActivationAsync(owner, command, default));
            Check(result.GetProperty("state").GetString() == "accepted" && relay.GovernanceReads == 1,
                "Governance mutation must succeed without rereading its retained capability context.");
        }
        Check(relay.DirectSends == 1 && HostSession(host).CredentialVersion == successor!.CredentialVersion &&
            f.Original.Transport.TokenRequests == tokens + 1 && admission.IsActive,
            "Locked recovery must adopt the proven refresh without another token request or replay.");
        Check(host.CurrentInstalledFirstUseFacts() is not null, "Strict installed identity must accept the recovered Host session.");
        await Finish(admission.RetireAsync());
        Console.WriteLine($"PASS ACHFU committed {resource} refresh then {(cancel ? "cancel" : "failure")} recovers before direct {direct}");
    }

    private static async Task GovernanceLockTimeoutIsNotSent()
    {
        foreach (var activate in new[] { true, false })
        foreach (var callerCancels in new[] { false, true })
            await GovernanceLockTimeoutIsNotSent(activate, callerCancels);
    }

    private static async Task GovernanceLockTimeoutIsNotSent(bool activate, bool callerCancels)
    {
        using var f = new Fixture();
        using var relay = new RecoveryRelay { Accept = _ => true };
        f.Original.Legacy = new(new("https://recovery.example.invalid/"), f.Credentials, relay);
        using var communities = new CommunityClient(new("https://recovery.example.invalid/"), relay);
        f.Original.Communities = communities;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Actual original admission required.");
        var host = f.Original.Host!; var owner = host.GameplayTimeContext!;
        await host.ReadOfficialFleetGovernanceContextAsync(owner, JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, sourceRef = "officialFleet:7", include = new[] { "role" } }), default);
        var sendsBefore = relay.DirectSends;
        var gate = (AccountMutationGate)host.GetType().GetField("_mutationGate", RecoveryFields)!.GetValue(host)!;
        var command = JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, sourceRef = "officialFleet:7", operationId = "lock-timeout-intent", expectedPolicyRevision = 2 });
        // The real deadline is 12 seconds; only its length is shortened here. The
        // caller-cancel case keeps it long so that cancellation is what ends the wait.
        host.GovernanceWriteDeadline = callerCancels ? TimeSpan.FromMinutes(1) : TimeSpan.FromMilliseconds(50);
        using var caller = new CancellationTokenSource();
        await gate.WaitAsync(default);
        try
        {
            var write = activate
                ? host.ActivateOfficialFleetGovernanceAsync(owner, command, caller.Token)
                : host.RevokeOfficialFleetGovernanceActivationAsync(owner, command, caller.Token);
            if (callerCancels) caller.Cancel();
            string outcome;
            try { await write; outcome = "completed"; }
            catch (AccountBridgeHostException error) { outcome = error.Code + (error.Retryable ? "/retryable" : ""); }
            catch (OperationCanceledException) { outcome = "cancelled"; }
            Check(outcome == (callerCancels ? "cancelled" : "communities.activationNotSent/retryable"),
                "A write stopped while waiting for the lock must report its real state, got " + outcome);
            Check(relay.DirectSends == sendsBefore, "A write stopped while waiting for the lock must never reach the relay.");
        }
        finally { gate.Release(); }
        await Finish(admission.RetireAsync());
        Console.WriteLine($"PASS ACHFU governance lock wait reports not sent: activate={activate} callerCancels={callerCancels}");
    }

    private static async Task DirectSnapshotGenerationFence()
    {
        using var f = new Fixture();
        using var relay = new RecoveryRelay { Accept = _ => true };
        f.Original.Legacy = new(new("https://recovery.example.invalid/"), f.Credentials, relay);
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Actual original admission required.");
        var host = f.Original.Host!; var owner = host.GameplayTimeContext!;
        var gate = (AccountMutationGate)host.GetType().GetField("_mutationGate", RecoveryFields)!.GetValue(host)!;
        var generationField = host.GetType().GetField("_generation", RecoveryFields)!;
        var generation = host.Generation;
        await gate.WaitAsync(default);
        var request = host.ReadAsync(owner, default);
        try
        {
            Check(!request.IsCompleted && relay.DirectSends == 0, "Direct snapshot must be queued behind the existing mutation.");
            // Model the lifecycle mutation at its protected generation boundary,
            // without a replacement identity or any unrelated account work.
            generationField.SetValue(host, generation + 1);
        }
        finally { gate.Release(); }
        var rejected = false;
        try { await request; }
        catch (BridgeStaleGenerationException) { rejected = true; }
        finally { generationField.SetValue(host, generation); }
        Check(rejected && relay.DirectSends == 0, "A generation change while awaiting the snapshot must reject before direct IO.");
        await Finish(admission.RetireAsync());
        Console.WriteLine("PASS ACHFU direct snapshot rejects a generation change before sending");
    }
}
