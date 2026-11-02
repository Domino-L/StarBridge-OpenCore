using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static class ScmAchievementUnlockTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "scm", "synthetic-achievement-owner");
    private static ScmAchievementItem Item(int id, DateTimeOffset? at = null, int order = 0) =>
        new($"scm-{id}", "星际圣诞", null, null, null, null, "RARE", "HOLIDAY", true, at, null, null, order);
    private static ScmAchievementCatalog Catalog(params ScmAchievementItem[] items) => new(1, DateTimeOffset.UtcNow, items);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-scm-unlocks-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            HolidayArtwork();
            await Detection(root);
            await Schedule(root + "-schedule", early: false);
            await Schedule(root + "-early", early: true);
            await SwitchDuringRead(root + "-switch");
            await ScmServerDate(root + "-date");
            await ScmAchievementReviewTests.Run(root);
            Console.WriteLine("PASS CX-ACHCEL SCM: 4 groups, 0 failed (baseline/recent/dedup/offline/accounts, 3/10/30 bound, early stop, stale read)");
        }
        finally
        {
            foreach (var path in new[] { root, root + "-schedule", root + "-early", root + "-switch", root + "-date" })
                if (Directory.Exists(path)) Directory.Delete(path, true);
        }
    }
    private static void HolidayArtwork()
    {
        Check(ScmAchievementPresentation.Artwork(Item(1) with { Name = "登高望远" }) ==
            "Assets/Achievements/scm-holiday-double-ninth-512.webp", "Double Ninth exact name resolves bundled artwork");
        Check(ScmAchievementPresentation.Artwork(Item(1) with { Name = "国庆节" }) ==
            "Assets/Achievements/scm-holiday-national-day-512.webp", "National Day exact name resolves bundled artwork");
        Check(ScmAchievementPresentation.Artwork(Item(1) with { Name = "未收录的节日" }) is null, "Unknown holiday remains without artwork");
        Console.WriteLine("PASS CX-ACHCEL holiday artwork: double-ninth, national-day, unknown null");
    }
    private static async Task Detection(string root)
    {
        var clock = new CelebrationTestClock(); var started = clock.GetUtcNow();
        (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
        var earned = new List<string>();
        ScmAchievementUnlockRuntime Create() => new(root, () => current, (_, _) => Task.CompletedTask,
            (_, _) => Task.FromResult(Catalog()), (_, item, _) => earned.Add(item.Id), clock, started);
        using (var runtime = Create())
        {
            Check(!await runtime.ObserveAsync(Owner, 1, Catalog(Item(1), Item(2, started.AddMinutes(-11)))) && earned.Count == 0, "First historical sync must not celebrate");
            Check(await runtime.ObserveAsync(Owner, 1, Catalog(Item(1), Item(3))) && earned.SequenceEqual(new[] { "scm-3" }), "New true unlock after baseline celebrates");
            Check(!await runtime.ObserveAsync(Owner, 1, Catalog(Item(3, started))) && earned.Count == 1, "Changed timestamp cannot replay the same ID");
            current = (Owner with { Subject = "synthetic-second" }, 2);
            Check(await runtime.ObserveAsync(current.Context!, 2, Catalog(Item(1), Item(4, started.AddMinutes(-9)))) && earned.Last() == "scm-4" && earned.Count == 2,
                "New account suppresses old history and permits recent exception on its first read");
            current = (Owner, 3);
            Check(!await runtime.ObserveAsync(Owner, 3, Catalog(Item(5))) && earned.Count == 2, "Switch-back first read is a baseline");
            var cache = new StarBridge.HostRuntime.Account.OfflineAccountStore(root);
            cache.Observe(Owner, "Synthetic cached display", () => true);
            cache.ObserveScmAchievements(Owner, Catalog(Item(6, started)), () => true);
            cache.ScmAchievementsRead = new ScmAchievementUnlockStore(root).ConfirmOffline;
            Check(cache.ReadSelectedScmAchievements(Owner, () => true) is not null && earned.Count == 2, "Actual offline snapshot read only acknowledges recent unlocks");
            Check(!await runtime.ObserveAsync(Owner, 3, Catalog(Item(6, started))), "Online read does not replay an acknowledged offline ID");
            Check(await runtime.ObserveAsync(Owner, 3, Catalog(Item(8, started, 2), Item(7, started, 1))) && earned.TakeLast(2).SequenceEqual(new[] { "scm-7", "scm-8" }),
                "Every new unlock is delivered in display order");
        }
        using var restarted = Create();
        Check(!await restarted.ObserveAsync(Owner, 3, Catalog(Item(7, started), Item(8, started))), "Persisted IDs survive process restart including recent timestamps");
        Check(ScmAchievementPresentation.Artwork(Item(1)) == "Assets/Achievements/scm-holiday-christmas-512.webp", "Exact holiday name resolves bundled artwork");
        Check(ScmAchievementPresentation.Artwork(Item(1) with { Name = "星际圣诞 extra" }) is null, "Unknown titles never guess artwork");
    }
    private static async Task Schedule(string root, bool early)
    {
        var clock = new CelebrationTestClock(); var triggered = 0; var reads = 0; var earned = 0;
        using var runtime = new ScmAchievementUnlockRuntime(root, () => (Owner, 1),
            (_, _) => { Interlocked.Increment(ref triggered); return Task.CompletedTask; },
            (_, _) => { Interlocked.Increment(ref reads); return Task.FromResult(early ? Catalog(Item(1, clock.GetUtcNow())) : Catalog()); },
            (_, _, _) => earned++, clock, clock.GetUtcNow());
        runtime.Wake();
        await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
        Check(triggered == 1 && reads == 0, "One daily user/get before delayed reads");
        clock.Advance(TimeSpan.FromSeconds(2)); Check(reads == 0, "No early SCM reread");
        clock.Advance(TimeSpan.FromSeconds(1));
        await CelebrationTestClock.Until(() => Volatile.Read(ref reads) == 1);
        if (early)
        {
            await CelebrationTestClock.Until(() => Volatile.Read(ref earned) == 1);
            clock.Advance(TimeSpan.FromDays(1)); await runtime.RetireAsync();
            Check(reads == 1, "New unlock stops remaining scheduled reads");
            return;
        }
        await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(7)));
        clock.Advance(TimeSpan.FromSeconds(7));
        await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(20)));
        Check(reads == 2, "Second read is at trigger plus 10 seconds");
        clock.Advance(TimeSpan.FromSeconds(20));
        await CelebrationTestClock.Until(() => Volatile.Read(ref reads) == 3);
        await runtime.WaitForIdleAsync();
        runtime.Wake(); await runtime.WaitForIdleAsync();
        Check(triggered == 1 && reads == 3, "Same local date is bounded to one trigger and three rereads");
        clock.Advance(TimeSpan.FromDays(1)); runtime.Wake();
        await CelebrationTestClock.Until(() => Volatile.Read(ref triggered) == 2);
        await runtime.RetireAsync();
        Check(reads == 3, "Retirement cancels the next day's delayed work");
        clock.Advance(TimeSpan.FromDays(-1));
        using var restarted = new ScmAchievementUnlockRuntime(root, () => (Owner, 1),
            (_, _) => { triggered++; return Task.CompletedTask; }, (_, _) => Task.FromResult(Catalog()), (_, _, _) => { }, clock);
        restarted.Wake(); await restarted.WaitForIdleAsync();
        Check(triggered == 2, "Restart and local clock rollback cannot repeat an already claimed date");
    }
    // The claim follows SCM's date. This clock's local zone is UTC, so a local
    // date would trigger at 00:00 UTC instead of 16:00 UTC.
    private static async Task ScmServerDate(string root)
    {
        var clock = new CelebrationTestClock(); var triggered = 0;
        using var runtime = new ScmAchievementUnlockRuntime(root, () => (Owner, 1),
            (_, _) => { Interlocked.Increment(ref triggered); return Task.CompletedTask; },
            (_, _) => Task.FromResult(Catalog()), (_, _, _) => { }, clock);
        async Task FinishRereads()
        {
            await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
            clock.Advance(TimeSpan.FromSeconds(3));
            await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(7)));
            clock.Advance(TimeSpan.FromSeconds(7));
            await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(20)));
            clock.Advance(TimeSpan.FromSeconds(20));
            await runtime.WaitForIdleAsync();
        }
        var now = clock.GetUtcNow();
        clock.Advance(new DateTimeOffset(now.UtcDateTime.Date.AddDays(1).AddHours(15).AddMinutes(50), TimeSpan.Zero) - now);
        runtime.Wake(); await FinishRereads();
        Check(triggered == 1, "First online moment of the SCM day triggers once");
        clock.Advance(TimeSpan.FromMinutes(5));
        runtime.Wake(); await runtime.WaitForIdleAsync();
        Check(triggered == 1, "Later checks on the same SCM date do not call again");
        clock.Advance(TimeSpan.FromMinutes(6));
        runtime.Wake(); await FinishRereads();
        Check(triggered == 2, "16:00 UTC starts the next SCM date for a client left open");
        clock.Advance(TimeSpan.FromHours(8) + TimeSpan.FromMinutes(1));
        runtime.Wake(); await runtime.WaitForIdleAsync();
        Check(triggered == 2, "00:00 UTC is not a new SCM date");
    }
    private static async Task SwitchDuringRead(string root)
    {
        var clock = new CelebrationTestClock();
        (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
        var held = new TaskCompletionSource<ScmAchievementCatalog>(TaskCreationOptions.RunContinuationsAsynchronously);
        var reading = false; var earned = 0;
        using var runtime = new ScmAchievementUnlockRuntime(root, () => current, (_, _) => Task.CompletedTask,
            (_, _) => { reading = true; return held.Task; }, (_, _, _) => earned++, clock, clock.GetUtcNow());
        runtime.Wake(); await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
        clock.Advance(TimeSpan.FromSeconds(3)); await CelebrationTestClock.Until(() => reading);
        current = (null, 2); runtime.Invalidate(2);
        held.SetResult(Catalog(Item(1, clock.GetUtcNow())));
        await runtime.WaitForIdleAsync();
        Check(earned == 0, "Late old-account read cannot celebrate after account switch");
    }
}
