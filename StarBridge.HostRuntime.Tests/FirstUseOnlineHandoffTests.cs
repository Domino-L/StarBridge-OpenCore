using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class FirstUseOnlineHandoffTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> work)
    { await work(); Console.WriteLine("PASS first-use online handoff: " + name); }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow.AddSeconds(1);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private static async Task Start(FirstUseOnlineReturnTests.Fixture f, bool confirm = true, TimeProvider? clock = null)
    {
        await f.Prepare(clock); f.Mode.RequestOnline(2, Id()); await f.Stage();
        Check((await f.Login().WaitAsync(TimeSpan.FromSeconds(3))).Response.Status == BridgeResponseStatuses.Ok,
            "Use the actual PKCE candidate owner.");
        if (!confirm) return;
        var review = await f.Mode.ReadOnlineIdentityAsync(3);
        Check((await f.Mode.ConfirmOnlineIdentityAsync(3, review.ConfirmationKey!)).State == "confirmedForHandoff",
            "Actual fresh readback and explicit confirmation are required.");
    }
    internal static async Task Run()
    {
        await Case("unconfirmed login cannot seal or prepare ownership", Unconfirmed);
        await Case("actual candidate drain preserves owner, local mode and deferred business", Prepared);
        await Case("bridge polling and rereview neither expose nor discard the live prepared owner", Polling);
        await Case("an ignored-cancellation identity read must physically exit before preparation", Drain);
        await Case("explicit cancellation can enter while authentication handoff is draining", DirectCancel);
        await Case("abandoned preparation remains sealed and cancellation still awaits actual exit", Abandoned);
        await Case("expired or stale revision confirmation cannot seal authentication", Stale);
        await Case("expiry during the actual drain cannot create a prepared owner", ExpiredDrain);
        await Case("local source change invalidates prepared ownership without merging profiles", ChangedSource);
        await Case("newer vault authorization invalidates preparation without clearing that version", ChangedCredential);
        await Case("closing the original mode invalidates prepared ownership", Closed);
    }
    private static async Task Unconfirmed()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f, confirm: false);
        var bytes = File.ReadAllBytes(f.VaultPath);
        Check(await f.Mode.PrepareOnlineHandoffAsync(3) is null && !f.Candidate!.FirstUseAuthenticationSealed &&
            f.Mode.LocalMode().Active && File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes),
            "A login snapshot is not approval or an authentication drain.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Prepared()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var local = f.Mode.LocalMode(); var generation = f.Candidate!.Generation;
        var bytes = File.ReadAllBytes(f.VaultPath); var requests = f.Transport.Requests;
        var prepared = await f.Mode.PrepareOnlineHandoffAsync(3);
        Check(prepared is { IsCurrent: true } && ReferenceEquals(prepared.Owner, f.Candidate) &&
            ReferenceEquals(await f.Mode.PrepareOnlineHandoffAsync(3), prepared) &&
            await f.Mode.PrepareOnlineHandoffAsync(2) is null &&
            f.Candidate.FirstUseAuthenticationSealed && f.Candidate.Generation == generation &&
            f.Mode.LocalMode() == local && f.Store.Read().Phase == "onlinePending" && f.Clock.Timers == 0 &&
            f.Transport.Requests == requests && File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes),
            "Preparation drains the original owner without restore, installation, account events or business startup.");
        var rejected = await f.Candidate.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), generation,
            new { schemaVersion = 1 }));
        Check(rejected.Response.Status != BridgeResponseStatuses.Ok && f.Transport.Requests == requests &&
            !f.Candidate.TryConfigureAccountBusiness(_ => throw new InvalidOperationException()) &&
            f.Mode.CurrentOnlineIdentity(3).State == "operationInProgress",
            "A prepared candidate still cannot admit authentication or installed business configuration.");
        f.Local.RequireLocalStateUnchanged();
        Check((await f.Cancel()).State == "local" && !prepared!.IsCurrent && f.Vault.LoadActiveAccountKey() is null,
            "Explicit original cancellation can retire the drained candidate and clean only its own authorization.");
    }
    private static async Task Drain()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        f.Transport.HoldIdentity = true;
        var read = f.Candidate!.ReadFirstUseIdentityAsync(f.Intent!, default);
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var preparation = f.Mode.PrepareOnlineHandoffAsync(3);
        Check(!preparation.IsCompleted && f.Transport.IdentityToken.IsCancellationRequested && f.Mode.LocalMode().Active,
            "Cancellation requested is not actual transport exit.");
        var requests = f.Transport.Requests;
        Check(f.Mode.CurrentOnlineIdentity(3).State == "operationInProgress" &&
            (await f.Mode.ReadOnlineIdentityAsync(3)).State == "operationInProgress",
            "Polling during the actual drain reports waiting and cannot discard the current handoff.");
        try
        {
            await f.Mode.PrepareOnlineHandoffAsync(3);
            throw new InvalidOperationException("Concurrent preparation must not duplicate the drain operation.");
        }
        catch (LocalFirstUseException error) when (error.Message == "firstUse.operation_in_progress") { }
        Check(f.Transport.Requests == requests, "Polling and duplicate preparation must not send another identity request.");
        f.Transport.ReleaseIdentity.TrySetResult();
        Check((await read.WaitAsync(TimeSpan.FromSeconds(3))).State == "contextChanged" &&
            await preparation.WaitAsync(TimeSpan.FromSeconds(3)) is { IsCurrent: true },
            "The original admission lease must exit before a live prepared owner is returned.");
        Check(f.Clock.Timers == 0 && f.Store.Read().Phase == "onlinePending", "No installation or publication occurred.");
    }
    private static async Task Polling()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var prepared = await f.Mode.PrepareOnlineHandoffAsync(3); var requests = f.Transport.Requests;
        var bridge = f.Local.Runtime.FirstUseOnlineReviewDispatcher!;
        foreach (var name in new[] { "read", "review" })
        {
            var batch = await bridge.DispatchAsync(BridgeEnvelope.Request("onboarding.onlineReview." + name, Id(),
                f.Local.Runtime.Generation, name == "read" ? (object)new { schemaVersion = 1 } :
                    new { schemaVersion = 1, revision = 3 }));
            var wire = System.Text.Json.JsonSerializer.Serialize(batch.Response.Payload);
            Check(batch.Response.Status == BridgeResponseStatuses.Ok && wire.Contains("operationInProgress") &&
                !wire.Contains("synthetic-access") && !wire.Contains("synthetic-subject") && !wire.Contains(f.Local.Root),
                "The pipe sees only waiting state, not the prepared Native owner or private identity.");
        }
        Check(prepared is { IsCurrent: true } && !await f.Mode.AuthenticateOnlineCandidateAsync(3, default) &&
            prepared!.IsCurrent && f.Transport.Requests == requests &&
            !FirstUseOnlineReviewBridgeDispatcher.Handles("onboarding.onlineReview.prepare"),
            "Polling and a rejected relogin cannot consume preparation or expose installation authority.");
    }
    private static async Task DirectCancel()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        f.Transport.HoldIdentity = true;
        var read = f.Candidate!.ReadFirstUseIdentityAsync(f.Intent!, default);
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var preparation = f.Mode.PrepareOnlineHandoffAsync(3);
        try
        {
            var cancel = f.Cancel();
            Check(!cancel.IsCompleted && f.Mode.LocalMode().Active && f.Vault.LoadActiveAccountKey() is not null,
                "Cancel must be admitted during handoff drain, not rejected by its mode writer; cleanup still awaits actual exit.");
            f.Transport.ReleaseIdentity.TrySetResult();
            await read.WaitAsync(TimeSpan.FromSeconds(3));
            Check(await preparation.WaitAsync(TimeSpan.FromSeconds(3)) is null &&
                (await cancel.WaitAsync(TimeSpan.FromSeconds(3))).State == "local" &&
                f.Vault.LoadActiveAccountKey() is null && f.Clock.Timers == 0,
                "Cancellation invalidates the late preparation and cleans only after the original request exits.");
            f.Local.RequireLocalStateUnchanged();
        }
        finally
        {
            f.Transport.ReleaseIdentity.TrySetResult();
            await read.WaitAsync(TimeSpan.FromSeconds(3));
            await preparation.WaitAsync(TimeSpan.FromSeconds(3));
        }
    }
    private static async Task Abandoned()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        f.Transport.HoldIdentity = true;
        var read = f.Candidate!.ReadFirstUseIdentityAsync(f.Intent!, default);
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        using var caller = new CancellationTokenSource();
        var preparation = f.Mode.PrepareOnlineHandoffAsync(3, caller.Token); caller.Cancel();
        try { await preparation; throw new InvalidOperationException("Caller cancellation must remain cancellation."); }
        catch (OperationCanceledException) { }
        Check(f.Mode.CurrentOnlineIdentity(3).State == "operationInProgress" && f.Candidate.FirstUseAuthenticationSealed &&
            f.Mode.LocalMode().Active && f.Vault.LoadActiveAccountKey() is not null,
            "Abandoning the wait cannot reopen admission or claim cleanup.");
        var cancel = f.Cancel();
        Check(!cancel.IsCompleted && f.Vault.LoadActiveAccountKey() is not null, "Cleanup still waits for the actual read.");
        f.Transport.ReleaseIdentity.TrySetResult(); await read.WaitAsync(TimeSpan.FromSeconds(3));
        Check((await cancel.WaitAsync(TimeSpan.FromSeconds(3))).State == "local" && f.Vault.LoadActiveAccountKey() is null,
            "The original cancellation path completes the original credential cleanup.");
    }
    private static async Task Stale()
    {
        var clock = new Clock(); using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f, clock: clock);
        Check(await f.Mode.PrepareOnlineHandoffAsync(2) is null && !f.Candidate!.FirstUseAuthenticationSealed,
            "The current confirmation cannot be claimed with another revision.");
        clock.Now += TimeSpan.FromMinutes(3);
        Check(await f.Mode.PrepareOnlineHandoffAsync(3) is null && !f.Candidate!.FirstUseAuthenticationSealed,
            "Expired proof cannot seal a still-live authentication owner.");
    }
    private static async Task ExpiredDrain()
    {
        var clock = new Clock(); using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f, clock: clock);
        f.Transport.HoldIdentity = true;
        var read = f.Candidate!.ReadFirstUseIdentityAsync(f.Intent!, default);
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var preparation = f.Mode.PrepareOnlineHandoffAsync(3);
        clock.Now += TimeSpan.FromMinutes(3); f.Transport.ReleaseIdentity.TrySetResult();
        await read.WaitAsync(TimeSpan.FromSeconds(3));
        Check(await preparation.WaitAsync(TimeSpan.FromSeconds(3)) is null &&
            f.Mode.CurrentOnlineIdentity(3).State == "operationInProgress" && f.Mode.LocalMode().Active,
            "A real drain doesn't revive expired review; local operation remains intact.");
        Check((await f.Cancel()).State == "local", "A failed preparation still supports explicit original retirement.");
    }
    private static async Task ChangedSource()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var prepared = await f.Mode.PrepareOnlineHandoffAsync(3);
        var local = new LocalFirstUseStore(f.Local.Root); var saved = local.Read();
        local.InvalidateSourceIdentity(saved.Revision, Id(), saved.SelectedSourceKey!, () => true);
        Check(prepared is not null && !prepared.IsCurrent && f.Clock.Timers == 0 && f.Store.Read().Phase == "onlinePending",
            "Prepared ownership is tied to the original confirmed local source, not a copied Handle.");
    }
    private static async Task ChangedCredential()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var prepared = await f.Mode.PrepareOnlineHandoffAsync(3);
        f.Vault.SaveRefreshToken("synthetic-replacement:other", "synthetic-new-refresh");
        var bytes = File.ReadAllBytes(f.VaultPath);
        Check(prepared is not null && !prepared.IsCurrent && (await f.Cancel()).State == "recoveryRequired" &&
            File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes) && f.Mode.LocalMode().Active,
            "Original credential ownership must not clear a newer selected version.");
    }
    private static async Task Closed()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await Start(f);
        var prepared = await f.Mode.PrepareOnlineHandoffAsync(3); f.Mode.Close();
        Check(prepared is not null && !prepared.IsCurrent && !f.Mode.LocalMode().Active,
            "The original mode's exit fence invalidates the live preparation.");
        Check(await f.Candidate!.RetireFirstUseOnlineCandidateAsync().WaitAsync(TimeSpan.FromSeconds(3)),
            "Mode exit still drains and retires its sole candidate owner.");
    }
}
