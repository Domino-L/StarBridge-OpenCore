using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class FirstUseGameIdentityTests
{
    private const string Handle = "Pilot-Example", Contact = "fixture-first-use-private-contact",
        Code = "fixture-first-use-private-code", Message = "fixture-first-use-private-rejection";
    private const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;
    private const string RequestCode = FirstUseOnlineReviewBridgeDispatcher.GameIdentityRequestCode,
        Verify = FirstUseOnlineReviewBridgeDispatcher.GameIdentityVerify,
        OpenProfile = FirstUseOnlineReviewBridgeDispatcher.GameIdentityOpenProfile;
    private static int _assertions;
    private static string Id() => Guid.NewGuid().ToString("N");
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private sealed class AssertionFailure(string description) : Exception(description);
    private static void Check(bool value, string description)
    { _assertions++; if (!value) throw new AssertionFailure(description); }

    internal static async Task Run()
    {
        _assertions = 0;
        var cases = new (string Name, Func<Task> Run)[] {
            ("code, verify, review, confirmation and original installation", Complete),
            ("authoritative Handle mismatch", Mismatch),
            ("rejections, permissions and unavailable responses", Outcomes),
            ("ambiguous and timed out writes reconcile once", Reconciliation),
            ("strict payload, revision, context and bridge generation", Validation),
            ("unauthenticated, local and unsupported identity states send nothing", Admission),
            ("fixed profile opener and in-progress sign-in admission", ProfileAndSignIn),
            ("single operation and free mutation lane", Concurrency),
            ("cooperative cancellation completes without deadlock", CooperativeCancel),
            ("ignoring cancellation drains before local return", CancelDrain),
            ("candidate retirement discards late authoritative read", RetireRead),
            ("changed credential and wire generation discard late results", ChangedOwner),
            ("retained resume verifies through the same candidate route", Retained),
            ("retained unverified entry blocks confirmation and installation until verified", RetainedUnverifiedEntry),
            ("retained entry preserves every authoritative verification state", RetainedEntryStates),
            ("retained verified entry preserves account-only restoration", RetainedVerifiedEntry),
            ("retained confirmation rechecks authoritative verification", RetainedConfirmationReadback),
            ("retained missing verification permission reauthorizes before verification and installation", RetainedMissingPermission),
            ("retained reauthorization without verification permission stays blocked", RetainedPermissionStillMissing),
            ("unexpired retained sessions reject unrelated reauthorization", RetainedReauthorizationAdmission),
            ("verified retained account without verification permission keeps account review", RetainedVerifiedMissingPermission),
            ("missing-permission reauthorization rejects another subject", RetainedPermissionWrongSubject),
            ("fresh missing verification permission permits another login", FreshMissingPermission),
            ("expired or 401 candidate never uses installed restoration", Authorization),
            ("private exception and diagnostic fields", Diagnostics)
        };
        var failures = 0;
        foreach (var (name, run) in cases)
        {
            try { await run(); Console.WriteLine("PASS first-use game identity " + name); }
            catch (Exception error) { failures++; Console.WriteLine("FAIL first-use game identity " + name + ": " +
                (error is AssertionFailure ? error.Message : error.GetType().Name)); }
        }
        Console.WriteLine($"SUMMARY first-use game identity passed={cases.Length - failures} failed={failures} assertions={_assertions}");
        if (failures != 0) throw new InvalidOperationException("First-use game identity regression failed.");
    }

    private sealed class Wire(FirstUseOnlineReturnTests.Transport transport)
    {
        internal string Mode = "ok";
        internal bool CommitAmbiguous, Hold, Cooperative, DropPermission;
        internal int Codes, Verifies;
        internal string VerifiedHandle = Handle;
        internal string? Rejection = Message;
        internal long? Expiry = 120;
        internal CancellationToken Token;
        internal readonly TaskCompletionSource Entered = Signal(), Release = Signal();
        internal async Task<HttpResponseMessage> Send(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri?.Host == "synthetic.example.invalid" && request.Method == HttpMethod.Post,
                "only injected candidate verification transport");
            var verify = request.RequestUri!.AbsolutePath.EndsWith("/verify", StringComparison.Ordinal);
            if (verify) Verifies++; else Codes++;
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Check(body.RootElement.GetProperty("gameName").GetString() == Handle, "request uses validated Handle");
            Check(!body.RootElement.TryGetProperty("revision", out _), "revision stays Native local");
            if (verify) Check(body.RootElement.GetProperty("userMobile").GetString() == Contact, "contact maps to existing SCM contract");
            Token = token; Entered.TrySetResult();
            if (Hold) { if (Cooperative) await Release.Task.WaitAsync(token); else await Release.Task; }
            if (verify && DropPermission) transport.Capabilities = ["profile.read"];
            if (verify && (Mode == "ok" || CommitAmbiguous))
            {
                transport.IdentityStatus = "VERIFIED"; transport.IdentityVerified = true;
                transport.Handle = VerifiedHandle; transport.NormalizedHandle = VerifiedHandle.ToLowerInvariant();
            }
            if (Mode == "timeout") throw new OperationCanceledException(Contact + Code, token);
            if (Mode == "network") throw new HttpRequestException(Contact + Message);
            if (Mode == "malformed") return new(HttpStatusCode.OK) { Content = new StringContent(Contact + Code) };
            var status = Mode switch { "forbidden" => HttpStatusCode.Forbidden, "unauthorized" => HttpStatusCode.Unauthorized,
                "gateway" => HttpStatusCode.BadGateway, "http-rejected" => HttpStatusCode.BadRequest, _ => HttpStatusCode.OK };
            return new(status) { Content = JsonContent.Create(new { available = Mode != "unavailable",
                success = Mode == "ok", message = Rejection, verificationCode = Code, expireTime = Expiry }) };
        }
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly FirstUseOnlineReturnTests.Fixture Original = new();
        internal readonly Wire Wire;
        internal FirstUseOnlineReviewBridgeDispatcher Bridge = null!;
        internal long Generation = 71;
        internal int AccountChanges, IdentityChanges, Events;
        internal byte[] Before = [];
        internal long OwnerGeneration;
        internal Fixture()
        {
            Original.Transport.IdentityStatus = "UNVERIFIED"; Original.Transport.IdentityVerified = false;
            Original.Transport.Capabilities = ["profile.read", "game_identity.verify"];
            Wire = new(Original.Transport); Original.Transport.GameIdentityRequest = Wire.Send;
        }
        internal async Task Start(bool login = true)
        {
            await Original.Prepare(); Original.Mode.RequestOnline(2, Id()); await Original.Stage();
            Bridge = new(Original.Mode, () => Generation); Bridge.EventReady += _ => Events++;
            if (login) { Check((await Original.Login()).Response.Status == "ok", "synthetic authorization completed"); Snapshot(); }
        }
        internal void Snapshot()
        {
            Before = File.ReadAllBytes(Original.VaultPath); OwnerGeneration = Original.Candidate!.Generation;
            Original.Host!.AccountChanged += _ => AccountChanges++;
            Original.Host.GameIdentityChanged += _ => IdentityChanges++;
        }
        internal Task<BridgeDispatchBatch> Send(string name, object? payload = null, CancellationToken token = default) =>
            Bridge.DispatchAsync(BridgeEnvelope.Request(name, Id(), Generation, payload ?? Payload(name, Original.Mode.Current.Revision)), token).AsTask();
        internal async Task<FirstUseOnlineIdentityObservation> Review()
        {
            var result = await Send(Original.Mode.RetainsOnlineReviewSession
                ? "onboarding.onlineReview.v2.review" : FirstUseOnlineReviewBridgeDispatcher.ReviewRequest,
                new { schemaVersion = Original.Mode.RetainsOnlineReviewSession ? 2 : 1, revision = Original.Mode.Current.Revision });
            Check(result.Response.Error is null, "review bridge succeeded");
            var state = result.Response.Payload.GetProperty("identity").GetProperty("state").GetString();
            var identity = result.Response.Payload.GetProperty("identity");
            return new(state!, identity.GetProperty("localHandle").GetString(),
                identity.GetProperty("authoritativeHandle").GetString(), identity.GetProperty("accountDisplayName").GetString(),
                identity.GetProperty("confirmationKey").GetString());
        }
        internal void Quiet()
        {
            Check(AccountChanges == 0 && IdentityChanges == 0 && Events == 0, "no installed pipeline event");
            Check(Original.Clock.Timers == 0 && Original.Host!.BusinessStartupDeferred &&
                Original.Host.GameplayTimeContext is null,
                "candidate business and enrollment stay deferred");
            Check(Original.Candidate!.Generation == OwnerGeneration && Original.Mode.LocalMode().Active &&
                Original.Store.Read().Phase == "onlinePending" && !Original.Mode.HasInstalledOnlineAccount,
                "same candidate generation, no installed account");
            Check(Original.Local.Host.CurrentContext is null && Original.Transport.Requests ==
                Original.Transport.TokenRequests + Original.Transport.IdentityRequests + Original.Transport.Revokes + Wire.Codes + Wire.Verifies,
                "no installed session or business registration POST/PUT");
            Check(File.ReadAllBytes(Original.VaultPath).SequenceEqual(Before) && Original.Transport.TokenRequests == 1 &&
                Original.Transport.Revokes == 0, "verification never saves, restores or retires authorization");
            Original.Local.RequireLocalStateUnchanged();
        }
        public void Dispose() { Wire.Release.TrySetResult(); Bridge?.Dispose(); Original.Dispose(); }
    }

    private static object Payload(string name, long revision) => name switch {
        RequestCode => new { schemaVersion = 1, revision, gameName = Handle },
        Verify => new { schemaVersion = 1, revision, gameName = Handle, contact = Contact },
        _ => new { schemaVersion = 1, revision }
    };
    private static void Outcome(BridgeDispatchBatch result, string outcome)
    {
        Check(result.Response.Error is null && result.Response.Status == "ok" && result.Response.AccountContext is null &&
            result.Events.Count == 0 && result.Response.Payload.GetProperty("schemaVersion").GetInt32() == 1 &&
            result.Response.Payload.GetProperty("outcome").GetString() == outcome, "expected candidate outcome " + outcome);
    }

    private static async Task Complete()
    {
        using var f = new Fixture(); await f.Start();
        Check((await f.Review()).State == "verificationRequired", "unverified candidate needs verification");
        Check(FirstUseOnlineReviewBridgeDispatcher.AdvertisedCapabilities.Contains(
            FirstUseOnlineReviewBridgeDispatcher.GameIdentityCapability), "online review advertises game identity");
        var code = await f.Send(RequestCode); Outcome(code, "issued");
        Check(code.Response.Payload.GetProperty("verificationCode").GetString() == Code &&
            code.Response.Payload.GetProperty("expiresInSeconds").GetInt64() == 120, "issued code contract");
        Outcome(await f.Send(Verify), "verified");
        var review = await f.Review(); Check(review is { State: "reviewRequired", AuthoritativeHandle: Handle }, "verification unlocks review");
        f.Quiet();
        var confirmed = await f.Send(FirstUseOnlineReviewBridgeDispatcher.ConfirmRequest,
            new { schemaVersion = 1, revision = 3, confirmationKey = review.ConfirmationKey });
        Check(confirmed.Response.Payload.GetProperty("identity").GetProperty("state").GetString() == "confirmedForHandoff",
            "existing explicit confirmation continues");
        f.Quiet();
        f.Original.Clock.AllowTimers = true;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await native.InstallConfirmedOnlineAsync(3, _ => { }).WaitAsync(TimeSpan.FromSeconds(5));
        Check(installed.State == "online" && f.Original.Mode.HasInstalledOnlineForCompletion, "existing original installation continues");
        Outcome(await f.Send(Verify), "unavailable");
        var account = await native.DispatchAsync(BridgeEnvelope.Request(GameIdentityBridge.RequestCode, Id(), native.Generation,
            new { schemaVersion = 1, gameName = Handle }, f.Original.Host!.CurrentContext));
        Check(account.Response.Error is null && account.Response.Payload.GetProperty("outcome").GetString() == "alreadyVerified",
            "installed account route keeps its original behavior");
        Check(f.Wire.Verifies == 1 && f.Wire.Codes == 1, "installed review cannot send candidate verification");
    }
    private static async Task Mismatch()
    {
        using var f = new Fixture(); await f.Start(); f.Wire.VerifiedHandle = "Other-Pilot";
        var result = await f.Send(Verify); Outcome(result, "verified");
        Check(result.Response.Payload.GetProperty("authoritativeHandle").GetString() == "Other-Pilot" &&
            (await f.Review()) is { State: "mismatch", ConfirmationKey: null } && !f.Original.Mode.HasConfirmedOnlineIdentity(3),
            "authoritative mismatch cannot install"); f.Quiet();
    }
    private static async Task Outcomes()
    {
        foreach (var command in new[] { RequestCode, Verify })
        foreach (var mode in new[] { "rejected", "http-rejected", "forbidden", "unavailable", "gateway", "malformed" })
        {
            using var f = new Fixture(); await f.Start(); f.Wire.Mode = mode;
            var result = await f.Send(command);
            Outcome(result, mode.EndsWith("rejected", StringComparison.Ordinal) ? "rejected" : mode == "forbidden"
                ? "reauthorizationRequired" : command == Verify ? "outcomeUnknown" : "unavailable"); f.Quiet();
            if (mode == "rejected") Check(result.Response.Payload.GetProperty("message").GetString() == Message, "private rejection on explicit response only");
        }
        using (var f = new Fixture())
        {
            f.Original.Transport.Capabilities = ["profile.read"]; await f.Start();
            Outcome(await f.Send(RequestCode), "reauthorizationRequired"); Outcome(await f.Send(Verify), "reauthorizationRequired");
            Check(f.Wire.Codes == 0 && f.Wire.Verifies == 0, "missing permission sends nothing"); f.Quiet();
        }
        using (var f = new Fixture())
        {
            await f.Start(); f.Wire.Mode = "rejected"; f.Wire.DropPermission = true;
            Outcome(await f.Send(Verify), "reauthorizationRequired"); f.Quiet();
        }
        using (var f = new Fixture())
        {
            await f.Start(); f.Wire.Mode = "rejected"; f.Wire.Rejection = null;
            Check((await f.Send(RequestCode)).Response.Payload.GetProperty("message").ValueKind == JsonValueKind.Null, "nullable message retained");
            f.Wire.Mode = "ok";
            foreach (var expiry in new long?[] { null, 0, -1 }) { f.Wire.Expiry = expiry; Outcome(await f.Send(RequestCode), "unavailable"); }
            f.Quiet();
        }
    }
    private static async Task Reconciliation()
    {
        foreach (var mode in new[] { "timeout", "network", "gateway", "unavailable" })
        foreach (var commit in new[] { false, true })
        {
            using var f = new Fixture(); await f.Start(); f.Wire.Mode = mode; f.Wire.CommitAmbiguous = commit;
            var before = f.Original.Transport.IdentityRequests;
            Outcome(await f.Send(Verify), commit ? "verified" : "outcomeUnknown");
            Check(f.Wire.Verifies == 1 && f.Original.Transport.IdentityRequests == before + 1, "one write and one bounded readback");
            Check((await f.Review()).State == (commit ? "reviewRequired" : "verificationRequired"), "review rereads authoritative result"); f.Quiet();
        }
        using var unavailable = new Fixture(); await unavailable.Start(); unavailable.Wire.Mode = "network";
        unavailable.Original.Transport.IdentityResponseStatus = HttpStatusCode.BadGateway;
        Outcome(await unavailable.Send(Verify), "outcomeUnknown"); unavailable.Quiet();
    }
    private static async Task Validation()
    {
        using var f = new Fixture(); await f.Start(); var before = f.Original.Transport.Requests;
        var invalid = new (string Command, object Payload)[] {
            (RequestCode, new { schemaVersion = 1, revision = 3, gameName = "ab" }),
            (RequestCode, new { schemaVersion = 1, revision = 3, gameName = "bad handle" }),
            (RequestCode, new { schemaVersion = "1", revision = 3, gameName = Handle }),
            (RequestCode, new { schemaVersion = 1, revision = 3, gameName = Handle, extra = true }),
            (Verify, new { schemaVersion = 1, revision = 3, gameName = Handle, contact = "short" }),
            (Verify, new { schemaVersion = 1, revision = 3, gameName = Handle, contact = new string('x', 257) }),
            (Verify, new { schemaVersion = 1, revision = 3, gameName = Handle, contact = (string?)null }),
            (OpenProfile, new { schemaVersion = 1, revision = 3, url = "https://example.invalid/" }),
            (OpenProfile, new { schemaVersion = 2, revision = 3 }), (OpenProfile, new { schemaVersion = 1 }) };
        foreach (var (command, payload) in invalid)
            Check((await f.Send(command, payload)).Response.Error?.Code == "firstUse.invalid_request", "invalid payload rejected");
        using var duplicate = JsonDocument.Parse("{\"schemaVersion\":1,\"revision\":3,\"gameName\":\"abc\",\"gameName\":\"def\"}");
        Check((await f.Send(RequestCode, duplicate.RootElement)).Response.Error?.Code == "firstUse.invalid_request", "duplicate rejected");
        foreach (var command in new[] { RequestCode, Verify, OpenProfile })
        foreach (var revision in new long[] { -1, 2, 4 })
            Check((await f.Send(command, Payload(command, revision))).Response.Error?.Code == "firstUse.context_changed", "stale revision rejected");
        var request = BridgeEnvelope.Request(Verify, Id(), f.Generation, Payload(Verify, 3), f.Original.Host!.CurrentContext);
        Check((await f.Bridge.DispatchAsync(request)).Response.Error?.Code == "firstUse.invalid_request", "candidate accepts no account context");
        Check((await f.Bridge.DispatchAsync(request with { AccountContext = null, SessionGeneration = 70 })).Response.Error?.Code ==
            "firstUse.context_changed", "stale pipe generation rejected");
        Check(f.Original.Transport.Requests == before && f.Original.BrowserOpens == 1, "invalid inputs send and open nothing"); f.Quiet();
    }
    private static async Task Admission()
    {
        using (var f = new Fixture())
        {
            await f.Start(login: false); Outcome(await f.Send(RequestCode), "unavailable");
            Check(!(await f.Send(OpenProfile)).Response.Payload.GetProperty("opened").GetBoolean(), "signed-out opener blocked");
            Check(f.Original.Transport.Requests == 0, "not signed in sends nothing");
            await f.Original.Cancel(); Outcome(await f.Send(Verify), "unavailable");
            Check(f.Original.Transport.Requests == 0, "local mode sends nothing");
        }
        foreach (var status in new[] { "PENDING", "UNKNOWN", "VERIFIED", "REVERIFY_REQUIRED", "REVOKED" })
        {
            using var f = new Fixture(); f.Original.Transport.IdentityStatus = status;
            f.Original.Transport.IdentityVerified = status == "VERIFIED"; await f.Start();
            Outcome(await f.Send(RequestCode), status == "VERIFIED" ? "alreadyVerified" :
                status is "REVERIFY_REQUIRED" or "REVOKED" ? "issued" : "unavailable");
            Check(f.Wire.Codes == (status is "REVERIFY_REQUIRED" or "REVOKED" ? 1 : 0), "only eligible authoritative states send"); f.Quiet();
        }
    }
    private static async Task Concurrency()
    {
        using var f = new Fixture(); await f.Start(); f.Wire.Hold = true;
        var work = f.Send(Verify); await f.Wire.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        try
        {
            Check((await f.Send(RequestCode)).Response.Error?.Code == "firstUse.operation_in_progress", "single operation rejects duplicate promptly");
            var gate = (AccountMutationGate)typeof(ScmAccountBridgeHost).GetField("_mutationGate", Private)!.GetValue(f.Original.Host)!;
            Check(await gate.WaitAsync(TimeSpan.Zero, default), "network does not own mutation gate"); gate.Release();
        }
        finally { f.Wire.Release.TrySetResult(); }
        Outcome(await work.WaitAsync(TimeSpan.FromSeconds(3)), "verified"); f.Quiet();
    }
    private static async Task ProfileAndSignIn()
    {
        using var f = new Fixture(); await f.Start(login: false);
        var opened = new List<Uri>(); f.Original.ProfileOpened = opened.Add;
        f.Original.Transport.HoldToken = true;
        var login = f.Original.Mode.AuthenticateOnlineCandidateAsync(3, default);
        await f.Original.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        try
        {
            Outcome(await f.Send(Verify), "unavailable");
            Check(!(await f.Send(OpenProfile)).Response.Payload.GetProperty("opened").GetBoolean() && opened.Count == 0,
                "in-progress sign-in cannot send or open profile");
        }
        finally { f.Original.Transport.ReleaseToken.TrySetResult(); }
        Check(await login.WaitAsync(TimeSpan.FromSeconds(3)), "original sign-in completes");
        if (f.Original.Callback is { } callback) await callback;
        f.Snapshot(); var requests = f.Original.Transport.Requests;
        var response = await f.Send(OpenProfile);
        Check(response.Response.AccountContext is null && response.Events.Count == 0 &&
            response.Response.Payload.GetProperty("opened").GetBoolean() && opened.Single().AbsoluteUri ==
            "https://robertsspaceindustries.com/account/profile" && f.Original.Transport.Requests == requests,
            "injected opener receives only fixed profile URL without HTTP");
        f.Quiet();
    }
    private static async Task CooperativeCancel()
    {
        using var f = new Fixture(); await f.Start(); f.Wire.Hold = true; f.Wire.Cooperative = true;
        var work = f.Send(Verify); await f.Wire.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check((await f.Original.Cancel().WaitAsync(TimeSpan.FromSeconds(3))).State == "local", "cancel does not deadlock on identity or mutation gate");
        Check((await work.WaitAsync(TimeSpan.FromSeconds(3))).Response.Error?.Code == "firstUse.context_changed", "cancelled owner cannot return result");
    }
    private static async Task CancelDrain()
    {
        using var f = new Fixture(); await f.Start(); f.Wire.Hold = true;
        var work = f.Send(Verify); await f.Wire.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var cancel = f.Original.Cancel();
        try { Check(!cancel.IsCompleted && f.Wire.Token.IsCancellationRequested, "cancel signals original lease and waits actual exit"); }
        finally { f.Wire.Release.TrySetResult(); }
        Check((await work.WaitAsync(TimeSpan.FromSeconds(3))).Response.Error?.Code == "firstUse.context_changed" &&
            (await cancel.WaitAsync(TimeSpan.FromSeconds(3))).State == "local", "late write neither submits identity nor blocks cancel");
        f.Original.Mode.RequestOnline(f.Original.Mode.Current.Revision, Id()); await f.Original.Stage(); await f.Original.Login();
        Check(f.Original.Candidate!.Generation > f.OwnerGeneration && f.Original.Clock.Timers == 0, "new candidate keeps its own generation");
    }
    private static async Task RetireRead()
    {
        using var f = new Fixture(); await f.Start(); f.Original.Transport.HoldIdentity = true;
        var work = f.Send(Verify); await f.Original.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var retiring = f.Original.Candidate!.RetireFirstUseOnlineCandidateAsync();
        try { Check(!retiring.IsCompleted && f.Original.Transport.IdentityToken.IsCancellationRequested, "readback participates in actual retirement"); }
        finally { f.Original.Transport.ReleaseIdentity.TrySetResult(); }
        Check((await work.WaitAsync(TimeSpan.FromSeconds(3))).Response.Error?.Code == "firstUse.context_changed" &&
            await retiring.WaitAsync(TimeSpan.FromSeconds(3)) && f.IdentityChanges == 0, "late read cannot commit or publish");
    }
    private static async Task ChangedOwner()
    {
        foreach (var wire in new[] { false, true })
        {
            using var f = new Fixture(); await f.Start(); f.Wire.Hold = true;
            var work = f.Send(Verify); await f.Wire.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            if (wire) f.Generation++;
            else f.Original.Vault.SaveRefreshToken("synthetic-scm:synthetic-subject", "synthetic-replacement");
            var bytes = File.ReadAllBytes(f.Original.VaultPath); f.Wire.Release.TrySetResult();
            var result = await work.WaitAsync(TimeSpan.FromSeconds(3));
            Check(result.Response.Error?.Code == "firstUse.context_changed" ||
                result.Response.Payload.TryGetProperty("outcome", out var outcome) && outcome.GetString() == "reauthorizationRequired",
                "superseded owner never reports success");
            Check(!f.Original.Host!.CurrentContext!.Subject.Contains("replacement", StringComparison.Ordinal) &&
                bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.IdentityRequests == 1 &&
                f.IdentityChanges == 0, "late result cannot replace authorization or start readback");
        }
    }
    private static async Task Retained()
    {
        await RetainedCore(false);
        await RetainedCore(true);
    }
    private static async Task StartVerified(Fixture f)
    {
        f.Original.Transport.IdentityStatus = "VERIFIED"; f.Original.Transport.IdentityVerified = true;
        await f.Start();
    }
    private static async Task<BridgeDispatchBatch> ResumeRetained(Fixture f, NativeAccountRuntimeBinding native,
        string status, bool accountOnly, bool mismatch = false)
    {
        var first = await f.Review();
        await f.Original.Mode.ConfirmOnlineIdentityAsync(3, first.ConfirmationKey!);
        f.Original.Clock.AllowTimers = true;
        Check((await native.InstallConfirmedOnlineAsync(3, _ => { }).WaitAsync(TimeSpan.FromSeconds(5))).State == "online",
            "fixture installs its originally verified account");
        Check((await f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation)).State == "offline",
            "original online owner exits before retained re-entry");
        if (accountOnly)
        {
            var local = new LocalFirstUseStore(f.Original.Local.Root); var saved = local.Read();
            local.SelectSource(saved.Revision, Id(), Path.Combine(f.Original.Local.Root, "other", "LIVE", "Game.log"), "LIVE", () => true);
        }
        if (mismatch)
        {
            f.Original.Transport.Handle = "Other-Pilot"; f.Original.Transport.NormalizedHandle = "other-pilot";
        }
        f.Original.Transport.IdentityStatus = status; f.Original.Transport.IdentityVerified = status == "VERIFIED";
        var begin = await RetainedAction(f, "begin");
        Check(begin.Response.Error is null, "v2 begin accepts explicit offline return");
        var resumed = await RetainedAction(f, "resume");
        Check(resumed.Response.Error is null && resumed.Response.Payload.GetProperty("retainsSession").GetBoolean(),
            "real v2 resume reads retained candidate without a preceding verification command");
        Check(f.Original.Mode.HasAuthenticatedOnlineCandidate == (status != "NEW_STATUS"),
            "retained authentication gate admits valid SCM states independently of verification");
        f.Snapshot(); f.AccountChanges = f.IdentityChanges = 0;
        return resumed;
    }
    private static Task<BridgeDispatchBatch> RetainedAction(Fixture f, string action, string? key = null) =>
        f.Send("onboarding.onlineReview.v2." + action, action == "confirm"
            ? new { schemaVersion = 2, revision = f.Original.Mode.Current.Revision, confirmationKey = key } as object
            : new { schemaVersion = 2, revision = f.Original.Mode.Current.Revision });
    private static void RetainedState(BridgeDispatchBatch batch, string state, bool key)
    {
        Check(batch.Response.Error is null, "retained bridge response succeeds");
        var identity = batch.Response.Payload.GetProperty("identity");
        Check(identity.GetProperty("state").GetString() == state &&
            (identity.GetProperty("confirmationKey").ValueKind == JsonValueKind.String) == key,
            "retained entry expects " + state + " with confirmationKey=" + key);
    }
    private static async Task RetainedBlocked(Fixture f, NativeAccountRuntimeBinding native)
    {
        var revision = f.Original.Mode.Current.Revision;
        Check(!f.Original.Mode.HasConfirmedOnlineAccount(revision) && !f.Original.Mode.HasConfirmedOnlineIdentity(revision),
            "blocked retained review issues no installation authority");
        Check((await RetainedAction(f, "confirm", Id())).Response.Error?.Code == "firstUse.context_changed",
            "invented confirmation key cannot confirm retained entry");
        try
        {
            await native.InstallConfirmedOnlineAsync(revision, _ => Check(false, "blocked composition must not run"));
            Check(false, "blocked retained entry cannot install");
        }
        catch (LocalFirstUseException error) { Check(error.Code == "firstUse.context_changed", "installation refuses unconfirmed identity"); }
        Check(f.Original.Mode.LocalMode().Active && !f.Original.Mode.HasInstalledOnlineAccount,
            "blocked retained candidate stays offline");
    }
    private static async Task RetainedUnverifiedEntry()
    {
        foreach (var accountOnly in new[] { false, true })
        {
            using var f = new Fixture(); await StartVerified(f);
            await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            RetainedState(await ResumeRetained(f, native, "UNVERIFIED", accountOnly), "verificationRequired", false);
            Check((await f.Review()) is { State: "verificationRequired", ConfirmationKey: null },
                "first retained review cannot bypass unverified SCM authority");
            await RetainedBlocked(f, native);
            Outcome(await f.Send(RequestCode), "issued"); Outcome(await f.Send(Verify), "verified");
            var review = await f.Review();
            Check(review.State == (accountOnly ? "accountReviewRequired" : "reviewRequired") && review.ConfirmationKey is not null,
                "verification restores the account-only or existing local Handle review");
            RetainedState(await RetainedAction(f, "confirm", review.ConfirmationKey),
                accountOnly ? "accountConfirmedForHandoff" : "confirmedForHandoff", false);
            Check((await native.InstallConfirmedOnlineAsync(f.Original.Mode.Current.Revision, _ => { })
                .WaitAsync(TimeSpan.FromSeconds(5))).State == "online", "verified retained candidate completes original installation");
            Check(f.Wire.Codes == 1 && f.Wire.Verifies == 1 && f.Original.BrowserOpens == 1,
                "retained verification uses the existing candidate route without another browser");
        }
    }
    private static async Task RetainedEntryStates()
    {
        foreach (var accountOnly in new[] { false, true })
        foreach (var (status, state) in new[] { ("PENDING", "verificationPending"), ("REVERIFY_REQUIRED", "reverifyRequired"),
            ("REVOKED", "revoked"), ("UNKNOWN", "unavailable"), ("NEW_STATUS", "unavailable") })
        {
            using var f = new Fixture(); await StartVerified(f);
            await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            RetainedState(await ResumeRetained(f, native, status, accountOnly), state, false);
            // Invalid protocol states fail resume before creating any session;
            // the following review must keep that candidate signed out.
            var reviewState = status == "NEW_STATUS" ? "signInRequired" : state;
            Check((await f.Review()) is { ConfirmationKey: null } review && review.State == reviewState,
                "retained review preserves " + reviewState);
            await RetainedBlocked(f, native);
            var eligible = status is "REVERIFY_REQUIRED" or "REVOKED";
            Outcome(await f.Send(RequestCode), eligible ? "issued" : "unavailable");
            Outcome(await f.Send(Verify), eligible ? "verified" : "unavailable");
            Check(f.Wire.Codes == (eligible ? 1 : 0) && f.Wire.Verifies == (eligible ? 1 : 0),
                "retained admission preserves existing eligible SCM verification states");
            Check((await f.Review()).State == (eligible ? accountOnly ? "accountReviewRequired" : "reviewRequired" : reviewState),
                "eligible retained verification can return to review");
        }
    }
    private static async Task RetainedVerifiedEntry()
    {
        foreach (var (accountOnly, mismatch) in new[] { (false, false), (true, false), (false, true) })
        {
            using var f = new Fixture(); await StartVerified(f);
            await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            var accountReview = accountOnly || mismatch;
            RetainedState(await ResumeRetained(f, native, "VERIFIED", accountOnly, mismatch),
                accountReview ? "accountReviewRequired" : "reviewRequired", true);
            var review = await f.Review();
            Check(review.State == (accountReview ? "accountReviewRequired" : "reviewRequired") &&
                (!accountReview || review.LocalHandle is null), "verified retained restoration needs no local Handle match");
            RetainedState(await RetainedAction(f, "confirm", review.ConfirmationKey),
                accountReview ? "accountConfirmedForHandoff" : "confirmedForHandoff", false);
            Check((await native.InstallConfirmedOnlineAsync(f.Original.Mode.Current.Revision, _ => { })
                .WaitAsync(TimeSpan.FromSeconds(5))).State == "online", "verified retained restoration still installs");
            Check(f.Wire.Codes == 0 && f.Wire.Verifies == 0 && f.Original.BrowserOpens == 1,
                "verified retained restoration requires no verification write or additional login");
        }
    }
    private static async Task RetainedConfirmationReadback()
    {
        using var f = new Fixture(); await StartVerified(f);
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var resumed = await ResumeRetained(f, native, "VERIFIED", accountOnly: true);
        var key = resumed.Response.Payload.GetProperty("identity").GetProperty("confirmationKey").GetString();
        f.Original.Transport.IdentityStatus = "REVOKED"; f.Original.Transport.IdentityVerified = false;
        RetainedState(await RetainedAction(f, "confirm", key), "revoked", false);
        await RetainedBlocked(f, native);
    }
    private static async Task RetainedMissingPermission()
    {
        foreach (var accountOnly in new[] { false, true })
        foreach (var (status, state) in new[] { ("UNVERIFIED", "verificationRequired"),
            ("REVERIFY_REQUIRED", "reverifyRequired"), ("REVOKED", "revoked") })
        {
            using var f = new Fixture(); await StartVerified(f);
            f.Original.Transport.Capabilities = ["profile.read"];
            await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            RetainedState(await ResumeRetained(f, native, status, accountOnly), "reauthorizationRequired", false);
            Check((await f.Review()) is { State: "reauthorizationRequired", ConfirmationKey: null },
                "retained review exposes missing verification permission");
            RetainedState(await f.Send("onboarding.onlineReview.v2.read", new { schemaVersion = 2 }),
                "reauthorizationRequired", false);
            await RetainedBlocked(f, native);
            var generation = f.Original.Candidate!.Generation; var timers = f.Original.Clock.Timers;
            f.Original.Transport.Capabilities = ["profile.read", "game_identity.verify"];
            RetainedState(await RetainedAction(f, "reauthorize"), state, false);
            Check((await f.Review()).State == state && f.Original.BrowserOpens == 2 &&
                f.Original.Candidate.Generation > generation && f.Original.Clock.Timers == timers &&
                f.Original.Host!.BusinessStartupDeferred && !f.Original.Mode.HasInstalledOnlineAccount,
                "explicit same-owner authorization repairs permission without installing or starting business");
            Outcome(await f.Send(Verify), "verified");
            var review = await f.Review();
            Check(review.State == (accountOnly ? "accountReviewRequired" : "reviewRequired") && review.ConfirmationKey is not null,
                "renewed permission still requires authoritative verification and explicit review");
            RetainedState(await RetainedAction(f, "confirm", review.ConfirmationKey),
                accountOnly ? "accountConfirmedForHandoff" : "confirmedForHandoff", false);
            Check((await native.InstallConfirmedOnlineAsync(f.Original.Mode.Current.Revision, _ => { })
                .WaitAsync(TimeSpan.FromSeconds(5))).State == "online", "reauthorized verified retained account installs");
        }
    }
    private static async Task RetainedPermissionStillMissing()
    {
        foreach (var status in new[] { "UNVERIFIED", "REVERIFY_REQUIRED", "REVOKED" })
        {
            using var f = new Fixture(); await StartVerified(f);
            f.Original.Transport.Capabilities = ["profile.read"];
            await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            RetainedState(await ResumeRetained(f, native, status, accountOnly: true), "reauthorizationRequired", false);
            for (var attempt = 0; attempt < 2; attempt++)
            {
                RetainedState(await RetainedAction(f, "reauthorize"), "reauthorizationRequired", false);
                Check((await f.Review()) is { State: "reauthorizationRequired", ConfirmationKey: null },
                    "authorization without permission cannot escape reauthorizationRequired");
                Outcome(await f.Send(Verify), "reauthorizationRequired");
                await RetainedBlocked(f, native);
            }
            Check(f.Original.BrowserOpens == 3 && f.Wire.Verifies == 0,
                "each explicit retry keeps the same original credential lineage and sends no verification write");
        }
    }
    private static async Task RetainedReauthorizationAdmission()
    {
        foreach (var (status, permission, state) in new[] { ("UNVERIFIED", true, "verificationRequired"),
            ("REVERIFY_REQUIRED", true, "reverifyRequired"), ("REVOKED", true, "revoked"),
            ("PENDING", false, "verificationPending"), ("UNKNOWN", false, "unavailable") })
        {
            using var f = new Fixture(); await StartVerified(f);
            f.Original.Transport.Capabilities = permission ? ["profile.read", "game_identity.verify"] : ["profile.read"];
            await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            RetainedState(await ResumeRetained(f, native, status, accountOnly: true), state, false);
            var requests = f.Original.Transport.Requests;
            Check((await RetainedAction(f, "reauthorize")).Response.Error?.Code == "firstUse.reauthorization_required",
                "unexpired retained " + status + " rejects reauthorization outside the permission repair case");
            Check(f.Original.BrowserOpens == 1 && f.Original.Transport.Requests == requests,
                "rejected reauthorization never opens a browser or sends a request");
        }
    }
    private static async Task RetainedVerifiedMissingPermission()
    {
        using var f = new Fixture(); await StartVerified(f);
        f.Original.Transport.Capabilities = ["profile.read"];
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        RetainedState(await ResumeRetained(f, native, "VERIFIED", accountOnly: true), "accountReviewRequired", true);
        Check((await RetainedAction(f, "reauthorize")).Response.Error?.Code == "firstUse.reauthorization_required" &&
            f.Original.BrowserOpens == 1, "verified account does not need permission repair");
        var review = await f.Review();
        Check(review is { State: "accountReviewRequired", ConfirmationKey: not null }, "verified account preserves account review");
        RetainedState(await RetainedAction(f, "confirm", review.ConfirmationKey), "accountConfirmedForHandoff", false);
        Check((await native.InstallConfirmedOnlineAsync(f.Original.Mode.Current.Revision, _ => { })
            .WaitAsync(TimeSpan.FromSeconds(5))).State == "online", "verified account installs without verification permission");
    }
    private static async Task RetainedPermissionWrongSubject()
    {
        using var f = new Fixture(); await StartVerified(f);
        f.Original.Transport.Capabilities = ["profile.read"];
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        RetainedState(await ResumeRetained(f, native, "UNVERIFIED", accountOnly: true), "reauthorizationRequired", false);
        var before = File.ReadAllBytes(f.Original.VaultPath); var generation = f.Original.Candidate!.Generation;
        f.Original.Transport.Subject = "different-synthetic-subject";
        f.Original.Transport.Capabilities = ["profile.read", "game_identity.verify"];
        RetainedState(await RetainedAction(f, "reauthorize"), "reauthorizationRequired", false);
        Check(f.Original.BrowserOpens == 2 && f.Original.Candidate.Generation == generation &&
            before.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
            "wrong browser subject cannot replace the retained principal, credential version or candidate generation");
        await RetainedBlocked(f, native);
    }
    private static async Task FreshMissingPermission()
    {
        foreach (var (status, state) in new[] { ("UNVERIFIED", "verificationRequired"),
            ("REVERIFY_REQUIRED", "reverifyRequired"), ("REVOKED", "revoked"),
            ("PENDING", "verificationPending"), ("UNKNOWN", "unavailable"), ("VERIFIED", "reviewRequired") })
        {
            using var f = new Fixture(); f.Original.Transport.IdentityStatus = status;
            f.Original.Transport.IdentityVerified = status == "VERIFIED";
            f.Original.Transport.Capabilities = ["profile.read"]; await f.Start();
            var needsPermission = status is "UNVERIFIED" or "REVERIFY_REQUIRED" or "REVOKED";
            var review = await f.Review();
            Check(review.State == (needsPermission ? "reauthorizationRequired" : state) &&
                (review.ConfirmationKey is not null) == (status == "VERIFIED"), "fresh candidate preserves precise permission admission");
            if (!needsPermission) continue;
            f.Original.Transport.Capabilities = ["profile.read", "game_identity.verify"];
            RetainedState(await f.Send(FirstUseOnlineReviewBridgeDispatcher.LoginRequest,
                new { schemaVersion = 1, revision = f.Original.Mode.Current.Revision }), state, false);
            Check(f.Original.BrowserOpens == 2 && (await f.Review()).State == state &&
                !f.Original.Mode.HasInstalledOnlineAccount, "fresh candidate can explicitly login again and still requires verification");
        }
    }
    private static async Task RetainedCore(bool mismatch)
    {
        using var f = new Fixture(); await f.Start(); Outcome(await f.Send(Verify), "verified");
        var review = await f.Review(); await f.Original.Mode.ConfirmOnlineIdentityAsync(3, review.ConfirmationKey!);
        f.Original.Clock.AllowTimers = true;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        await native.InstallConfirmedOnlineAsync(3, _ => { }).WaitAsync(TimeSpan.FromSeconds(5));
        Check((await f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation)).State == "offline", "original installation exits offline");
        f.Original.Transport.IdentityStatus = "REVERIFY_REQUIRED"; f.Original.Transport.IdentityVerified = false;
        f.Original.Mode.RequestResume(6, Id());
        Check(await f.Original.Mode.ResumeOnlineCandidateAsync(7) == "observed", "retained original session resumes");
        var browser = f.Original.BrowserOpens; var bytes = File.ReadAllBytes(f.Original.VaultPath);
        f.Snapshot(); // Observe the newly resumed host, not the retired fresh one.
        var generation = f.Original.Candidate!.Generation; f.AccountChanges = f.IdentityChanges = 0;
        var requests = f.Original.Transport.Requests; var timers = f.Original.Clock.Timers;
        if (mismatch) f.Wire.VerifiedHandle = "Other-Pilot";
        Outcome(await f.Send(RequestCode), "issued");
        Check((await f.Review()).State == "reverifyRequired", "issuing a code cannot become retained account-only confirmation");
        Outcome(await f.Send(Verify), "verified");
        Check((await f.Review()).State == (mismatch ? "mismatch" : "reviewRequired") && f.Original.Candidate.Generation == generation &&
            f.Original.BrowserOpens == browser && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) &&
            f.AccountChanges == 0 && f.IdentityChanges == 0 && !f.Original.Mode.HasInstalledOnlineAccount,
            "v1 game command supports retained candidates without publication or credential save");
        Check(f.Original.Transport.Requests == requests + 5 && f.Original.Clock.Timers == timers &&
            f.Original.Host!.BusinessStartupDeferred, "retained verification cannot wake registration or business loops");
    }
    private static async Task Authorization()
    {
        using (var f = new Fixture())
        {
            await f.Start(); f.Wire.Mode = "unauthorized";
            Outcome(await f.Send(RequestCode), "reauthorizationRequired"); Outcome(await f.Send(Verify), "reauthorizationRequired");
            Check(f.Original.Transport.IdentityRequests == 1, "401 cannot restore or reconcile another session"); f.Quiet();
        }
        using var expired = new Fixture(); var time = new FirstUseOnlineReturnTests.FrozenSessionTime();
        expired.Original.SessionTime = time; expired.Original.Transport.TokenLifetimeSeconds = 1; await expired.Start();
        time.Now += TimeSpan.FromSeconds(2); var before = expired.Original.Transport.Requests;
        Outcome(await expired.Send(Verify), "unavailable");
        Check(expired.Original.Transport.Requests == before, "expired candidate cannot enter installed refresh");
    }
    private static async Task Diagnostics()
    {
        foreach (var mode in new[] { "network", "timeout", "forbidden", "malformed" })
        {
            using var f = new Fixture(); await f.Start(); f.Wire.Mode = mode;
            await f.Send(RequestCode); await f.Send(Verify);
            var oauth = (OAuthPkceClient)typeof(ScmAccountBridgeHost).GetField("_oauth", Private)!.GetValue(f.Original.Host)!;
            var session = (ScmOAuthSession)typeof(ScmAccountBridgeHost).GetField("_session", Private)!.GetValue(f.Original.Host)!;
            try { await oauth.GetFirstUseGameIdentityCodeAsync(session, Handle, default); Check(false, "transport must fail"); }
            catch (Exception error) when (error is HttpRequestException or OperationCanceledException or ScmApiProtocolException)
            {
                foreach (var value in new[] { Handle, Contact, Code, Message })
                    Check(!error.Message.Contains(value, StringComparison.Ordinal), "private field excluded from exception");
                Check(error.InnerException is null, "private transport inner exception excluded");
            }
            var logs = Directory.GetFiles(HostDataRoot.CurrentRoot, "*.log", SearchOption.AllDirectories);
            Check(logs.Length > 0, "actual diagnostics exercised");
            foreach (var path in logs)
            foreach (var value in new[] { Handle, Handle.ToLowerInvariant(), Contact, Code, Message })
                Check(!File.ReadAllText(path).Contains(value, StringComparison.Ordinal), "private fields excluded from diagnostics");
        }
    }
}
