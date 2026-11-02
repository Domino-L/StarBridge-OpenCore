using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunReauthorizationProtocol()
    {
        await Case("expired retained session requires explicit same-owner browser reauthorization", ReauthorizationSuccess);
        await Case("wrong account reauthorization preserves original credentials and stays offline", ReauthorizationWrongAccount);
        await Case("newer login cannot be replaced by late explicit reauthorization", () => ReauthorizationReplacement(false));
        await Case("reauthorization cannot adopt a newer login selected before the browser action", ReauthorizationBeforeClick);
        await Case("expired staged access token permits only explicit original-account reauthorization", ReauthorizationExpired);
        await Case("reauthorization cancellation waits actual transport and retains offline credentials", () => ReauthorizationReplacement(true));
    }

    private static async Task ReauthorizationPending(Fixture f, NativeAccountRuntimeBinding native)
    {
        f.Original.Clock.AllowTimers = true; await f.Start();
        await EnterOffline(f, native);
        await ResumeWire(f.Original, "begin");
        f.Original.Transport.RejectRefresh = true;
        var before = File.ReadAllBytes(f.Original.VaultPath);
        RetainedWire(await ResumeWire(f.Original, "resume"), "signInRequired", "reauthorizationRequired");
        RetainedWire(await ResumeWire(f.Original, "read"), "signInRequired", "reauthorizationRequired");
        Check(f.Original.BrowserOpens == 1 && before.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
            "Rejected refresh and reads do not open a browser or delete the old credential");
    }
    private static async Task ReauthorizationSuccess()
    {
        using var f = new Fixture();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        await ReauthorizationPending(f, native);
        var timers = f.Original.Clock.Timers;
        var response = await ResumeWire(f.Original, "reauthorize");
        RetainedWire(response, "signInRequired", "reviewRequired");
        Check(f.Original.BrowserOpens == 2 && f.Original.Transport.LastGrant!.Contains("grant_type=authorization_code") &&
            f.Original.Clock.Timers == timers && !f.Original.Mode.HasInstalledOnlineForCompletion,
            "Only an explicit browser action authenticates; it cannot install or start online business");
        Check((await ResumeWire(f.Original, "reauthorize")).Response.Status != "ok", "Successful authorization cannot be replayed as another browser login");
        var key = response.Response.Payload.GetProperty("identity").GetProperty("confirmationKey").GetString();
        RetainedWire(await ResumeWire(f.Original, "confirm", key: key), "signInRequired", "confirmedForHandoff");
        Check((await native.InstallConfirmedOnlineAsync(f.Original.Mode.Current.Revision, _ => { })).State == "online",
            "The explicitly reviewed original reauthorized graph may use the one Native installation flow");
        Check(f.Original.Transport.Revokes == 0 && f.Original.Vault.LoadActiveAccountKey() is not null, "Reauthorization does not revoke retained login");
    }
    private static async Task ReauthorizationWrongAccount()
    {
        using var f = new Fixture();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        await ReauthorizationPending(f, native);
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        f.Original.Transport.Subject = "different-synthetic-subject";
        RetainedWire(await ResumeWire(f.Original, "reauthorize"), "signInRequired", "reauthorizationRequired");
        Check(bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Mode.LocalMode().Active &&
            !f.Original.Mode.HasAuthenticatedOnlineCandidate && f.Original.Transport.Revokes == 0,
            "Wrong browser account cannot change credentials, profiles or online ownership");
        RetainedWire(await ResumeWire(f.Original, "cancel"), "offline", "notStarted");
    }
    private static async Task ReauthorizationReplacement(bool cancel)
    {
        using var f = new Fixture();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        await ReauthorizationPending(f, native);
        f.Original.Transport.HoldToken = true;
        var tokens = f.Original.Transport.TokenRequests;
        var work = ResumeWire(f.Original, "reauthorize");
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (f.Original.Transport.TokenRequests == tokens && DateTime.UtcNow < deadline) await Task.Delay(5);
        Check(f.Original.Transport.TokenRequests == tokens + 1, "Actual browser token exchange must be held");
        if (!cancel) f.Original.Vault.SaveRefreshToken("synthetic-scm:synthetic-subject", "synthetic-newer-login");
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var exit = cancel ? ResumeWire(f.Original, "cancel") : null;
        try
        {
            if (exit is not null) Check(!exit.IsCompleted, "Cancellation cannot acknowledge a physically held OAuth exchange");
            f.Original.Transport.ReleaseToken.TrySetResult();
            var result = await work.WaitAsync(TimeSpan.FromSeconds(5));
            Check(result.Response.Status != "ok" || result.Response.Payload.GetProperty("identity").GetProperty("state").GetString() != "reviewRequired",
                "A late lost-context reauthorization cannot issue review authority");
            if (exit is not null) RetainedWire(await exit.WaitAsync(TimeSpan.FromSeconds(5)), "offline", "notStarted");
            Check(bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0 &&
                f.Original.Mode.LocalMode().Active, "Late authentication preserves original/newer credentials and local mode");
        }
        finally { f.Original.Transport.ReleaseToken.TrySetResult(); }
    }
    private static async Task ReauthorizationBeforeClick()
    {
        foreach (var key in new[] { "synthetic-scm:synthetic-subject", "synthetic-scm:different-owner" })
        {
            using var f = new Fixture();
            await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
            await ReauthorizationPending(f, native);
            f.Original.Vault.SaveRefreshToken(key, "synthetic-newer-login");
            var bytes = File.ReadAllBytes(f.Original.VaultPath);
            var result = await ResumeWire(f.Original, "reauthorize");
            Check(result.Response.Status != "ok" || result.Response.Payload.GetProperty("identity").GetProperty("state").GetString() == "contextChanged",
                "Lost original credential lineage cannot issue a new review");
            RetainedWire(await ResumeWire(f.Original, "resume"), "signInRequired", "contextChanged");
            Check(f.Original.BrowserOpens == 1 && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
                "The old resume cannot select a newer stored login or open its browser");
        }
    }
    private static async Task ReauthorizationExpired()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        var time = new FirstUseOnlineReturnTests.FrozenSessionTime(); f.Original.SessionTime = time; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        await EnterOffline(f, native); await ResumeWire(f.Original, "begin");
        f.Original.Transport.TokenLifetimeSeconds = 1;
        RetainedWire(await ResumeWire(f.Original, "resume"), "signInRequired", "reviewRequired");
        time.Now += TimeSpan.FromMilliseconds(1200);
        RetainedWire(await ResumeWire(f.Original, "read"), "signInRequired", "sessionExpired");
        f.Original.Transport.TokenLifetimeSeconds = 3600;
        RetainedWire(await ResumeWire(f.Original, "reauthorize"), "signInRequired", "reviewRequired");
        Check(f.Original.BrowserOpens == 2 && f.Original.Transport.Revokes == 0 && !f.Original.Mode.HasInstalledOnlineForCompletion,
            "Expired access requires a user browser action and renewed review, never automatic installation");
    }
}
