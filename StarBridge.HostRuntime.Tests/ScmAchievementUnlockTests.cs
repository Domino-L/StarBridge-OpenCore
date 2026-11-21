using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static class ScmAchievementUnlockTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "scm", "synthetic-achievement-owner");
    private static ScmAchievementItem Item(int id, DateTimeOffset? at = null, int order = 0) =>
        new($"scm-{id}", "星际圣诞", null, null, null, null, "RARE", "HOLIDAY", true, at, null, null, order);
    private static ScmAchievementCatalog Catalog(params ScmAchievementItem[] items) => new(1, DateTimeOffset.UtcNow, items);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    // What a receiver does after a card's visible dwell (AchievementCelebration.MarkPresented).
    internal static void Shown(string root, BridgeAccountContext owner, string receipt) =>
        new ScmAchievementUnlockStore(root).MarkPresented(owner, [receipt], () => true);
    internal static ScmAchievementUnlockStore.PendingUnlock[] Pending(string root, BridgeAccountContext owner)
    {
        using var lease = new ScmAchievementUnlockStore(root).Open(owner);
        return ScmAchievementUnlockStore.Unshown(lease.Read());
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-scm-unlocks-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            HolidayArtwork();
            DisplayNames();
            await Detection(root);
            await Schedule(root + "-schedule", early: false);
            await Schedule(root + "-early", early: true);
            await SwitchDuringRead(root + "-switch");
            await ScmServerDate(root + "-date");
            await ProductionStartup(root + "-production");
            await FailedBaselineRead(root + "-failed-baseline");
            await ScmAchievementReviewTests.Run(root);
            Console.WriteLine("PASS CX-ACHCEL SCM: 5 groups, 0 failed (baseline/recent/dedup/offline/accounts, 3/10/30 bound, early stop, stale read, production startup)");
        }
        finally
        {
            foreach (var path in new[] { root, root + "-schedule", root + "-early", root + "-switch", root + "-date", root + "-production", root + "-failed-baseline" })
                for (var attempt = 0; Directory.Exists(path); attempt++)
                {
                    // A shown card's acknowledgement may still be finishing its write.
                    try { Directory.Delete(path, true); }
                    catch (IOException) when (attempt < 40) { Thread.Sleep(50); }
                }
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
    // Build 104 (user 11-21): the card said 资深玩家 (SCM `name`) while the
    // collection said 中登 (SCM `title`). The card now follows the collection.
    private static void DisplayNames()
    {
        var daily = Item(1) with { Name = "资深玩家", Title = "中登", Type = "NORMAL" };
        Check(ScmAchievementPresentation.DisplayName(daily) == "中登", "Card uses SCM title, not name");
        Check(ScmAchievementPresentation.Artwork(daily) == "Assets/Achievements/scm-daily-account-regular-512.webp", "中登 card gets its daily art by title");
        foreach (var (title, expected) in new (string?, string)[] {
            (" ✨中登✨ ", "中登"), ("🎉 中登 🎉", "中登"), ("★·中登·★", "中登"), ("中登️", "中登"),
            ("中 登", "中 登"), ("中登！", "中登！"), (null, "资深玩家"), ("", "资深玩家"), (" ★ ", "资深玩家"), ("🎉", "资深玩家") })
            Check(ScmAchievementPresentation.DisplayName(daily with { Title = title }) == expected,
                $"Title {title ?? "null"} displays as {expected}");
        Check(ScmAchievementPresentation.DisplayName(daily with { Title = null, Name = "资深\n玩家\t" }) == "资深 玩家 ",
            "Fallback name keeps the single-line card rule");
        var holiday = Item(1) with { Name = "圣诞节成就", Title = "✨星际圣诞！" };
        Check(ScmAchievementPresentation.DisplayName(holiday) == "星际圣诞！", "Holiday card shows the cleaned title");
        Check(ScmAchievementPresentation.Artwork(holiday) == "Assets/Achievements/scm-holiday-christmas-512.webp",
            "Holiday art matches the title, ignoring a trailing exclamation mark");
        Check(ScmAchievementPresentation.Artwork(Item(1) with { Name = "星际圣诞", Title = "别的节日" }) is null,
            "Holiday art follows the shown title, never the hidden name");
        Console.WriteLine("PASS CX-ACHCEL SCM display names: title over name, symbol trim, fallback, holiday art by title");
        CardArtwork();
    }
    // Build 105 (user chose "赶进 105"): daily and limited-event cards carry the
    // same approved art as the collection, by exact title as scm_holiday_art.dart.
    private static void CardArtwork()
    {
        string? Art(string type, string title) => ScmAchievementPresentation.Artwork(Item(1) with { Name = "SCM name", Title = title, Type = type });
        foreach (var (title, slug) in new[] { ("萌新启航", "account-rookie"), ("中登", "account-regular"), ("纵横星海", "account-veteran"),
            ("攻略新手", "guide-beginner"), ("攻略达人", "guide-adept"), ("攻略大师", "guide-master"), ("初涉商海", "trade-beginner"),
            ("商业精英", "trade-adept"), ("商业大亨", "trade-master"), ("猎头帮", "bounty-beginner"), ("猎头帮首脑", "bounty-leader") })
        {
            Check(Art("NORMAL", title) == $"Assets/Achievements/scm-daily-{slug}-512.webp", $"Daily {title} art");
            Check(Art("SPECIAL", title) == $"Assets/Achievements/scm-daily-{slug}-512.webp", $"Special {title} art");
            Check(Art("EVENT_LIMITED", title) is null && Art("HOLIDAY", title) is null && Art("HIDDEN", title) is null, $"{title} art stays in its own group");
        }
        foreach (var (title, slug) in new[] { ("春节精英", "spring-elite"), ("签到达人", "checkin-streak"), ("春节欢庆", "spring-participant") })
        {
            Check(Art("EVENT_LIMITED", title) == $"Assets/Achievements/scm-event-{slug}-512.webp", $"Limited event {title} art");
            Check(Art("EVENT_LIMITED", title + "！") == $"Assets/Achievements/scm-event-{slug}-512.webp", $"Limited event {title}！ art");
            Check(Art("NORMAL", title) is null, $"{title} is not daily art");
        }
        Check(Art("HOLIDAY", "春节欢庆!") == "Assets/Achievements/scm-event-spring-participant-512.webp",
            "春节欢庆! listed under holidays reuses the limited-event art");
        Check(Art("HOLIDAY", "星际鬼才") == "Assets/Achievements/scm-holiday-halloween-512.webp", "Holiday art unchanged");
        Check(Art("NORMAL", "中登！") is null, "Daily titles do not drop a trailing exclamation mark");
        Check(Art("NORMAL", "中登 extra") is null && Art("NORMAL", "登") is null, "Never a substring match");
        Check(Art("HIDDEN", "中登") is null, "Hidden rows never get art");
        Console.WriteLine("PASS CX-ACHCEL SCM card art: 11 daily, 3 limited events, 春节欢庆 under holidays, exact titles only");
    }
    private static async Task Detection(string root)
    {
        var clock = new CelebrationTestClock(); var started = clock.GetUtcNow();
        (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
        var earned = new List<string>();
        ScmAchievementUnlockRuntime Create() => new(root, () => current, (_, _) => Task.CompletedTask,
            (_, _) => Task.FromResult(Catalog()), (_, item, receipt) => { earned.Add(item.Id); Shown(root, current.Context!, receipt); }, clock, started);
        using (var runtime = Create())
        {
            Check(!await runtime.ObserveAsync(Owner, 1, Catalog(Item(1), Item(2, started.AddMinutes(-11)))) && earned.Count == 0, "An account's first sync must not celebrate history");
            Check(await runtime.ObserveAsync(Owner, 1, Catalog(Item(1), Item(3))) && earned.SequenceEqual(new[] { "scm-3" }), "New true unlock after baseline celebrates");
            Check(!await runtime.ObserveAsync(Owner, 1, Catalog(Item(3, started))) && earned.Count == 1, "A shown ID never replays, even with a changed timestamp");
            current = (Owner with { Subject = "synthetic-second" }, 2);
            Check(await runtime.ObserveAsync(current.Context!, 2, Catalog(Item(1), Item(4, started.AddMinutes(-9)))) && earned.Last() == "scm-4" && earned.Count == 2,
                "New account suppresses old history and permits recent exception on its first read");
            current = (Owner, 3);
            Check(await runtime.ObserveAsync(Owner, 3, Catalog(Item(5))) && earned.Last() == "scm-5" && earned.Count == 3,
                "Build 105: returning to an account celebrates what it unlocked meanwhile");
            var cache = new StarBridge.HostRuntime.Account.OfflineAccountStore(root);
            cache.Observe(Owner, "Synthetic cached display", () => true);
            cache.ObserveScmAchievements(Owner, Catalog(Item(6, started)), () => true);
            cache.ScmAchievementsRead = new ScmAchievementUnlockStore(root).ConfirmOffline;
            Check(cache.ReadSelectedScmAchievements(Owner, () => true) is not null && earned.Count == 3 && Pending(root, Owner).Single().Item.Id == "scm-6",
                "An offline cache read keeps a new unlock pending instead of absorbing it");
            Check(!await runtime.ObserveAsync(Owner, 3, Catalog(Item(6, started))) && earned.Last() == "scm-6" && earned.Count == 4 && Pending(root, Owner).Length == 0,
                "The next online moment shows the unlock found offline, once");
            Check(await runtime.ObserveAsync(Owner, 3, Catalog(Item(8, started, 2), Item(7, started, 1))) && earned.TakeLast(2).SequenceEqual(new[] { "scm-7", "scm-8" }),
                "Every new unlock is delivered in display order");
        }
        using var restarted = Create();
        Check(!await restarted.ObserveAsync(Owner, 3, Catalog(Item(7, started), Item(8, started))) && earned.Count == 6, "Shown IDs survive process restart including recent timestamps");
        Check(ScmAchievementPresentation.Artwork(Item(1)) == "Assets/Achievements/scm-holiday-christmas-512.webp", "Exact holiday name resolves bundled artwork");
        Check(ScmAchievementPresentation.Artwork(Item(1) with { Name = "星际圣诞 extra" }) is null, "Unknown titles never guess artwork");
    }
    private static async Task Schedule(string root, bool early)
    {
        var clock = new CelebrationTestClock(); var triggered = 0; var reads = 0; var earned = 0;
        using var runtime = new ScmAchievementUnlockRuntime(root, () => (Owner, 1),
            (_, _) => { Interlocked.Increment(ref triggered); return Task.CompletedTask; },
            (_, _) => { var read = Interlocked.Increment(ref reads); return Task.FromResult(early && read > 1 ? Catalog(Item(1, clock.GetUtcNow())) : Catalog()); },
            (_, _, receipt) => { Interlocked.Increment(ref earned); Shown(root, Owner, receipt); }, clock, clock.GetUtcNow());
        runtime.Wake();
        await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
        Check(triggered == 1 && reads == 1, "Build 105: one baseline read, then the daily user/get, before delayed reads");
        clock.Advance(TimeSpan.FromSeconds(2)); Check(reads == 1, "No early SCM reread");
        clock.Advance(TimeSpan.FromSeconds(1));
        await CelebrationTestClock.Until(() => Volatile.Read(ref reads) == 2);
        if (early)
        {
            await CelebrationTestClock.Until(() => Volatile.Read(ref earned) == 1);
            clock.Advance(TimeSpan.FromDays(1)); await runtime.RetireAsync();
            Check(reads == 2, "New unlock stops remaining scheduled reads");
            return;
        }
        await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(7)));
        clock.Advance(TimeSpan.FromSeconds(7));
        await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(20)));
        Check(reads == 3, "Second reread is at trigger plus 10 seconds");
        clock.Advance(TimeSpan.FromSeconds(20));
        await CelebrationTestClock.Until(() => Volatile.Read(ref reads) == 4);
        await runtime.WaitForIdleAsync();
        runtime.Wake(); await runtime.WaitForIdleAsync();
        Check(triggered == 1 && reads == 4, "Same local date is bounded to one trigger, one baseline read and three rereads");
        clock.Advance(TimeSpan.FromDays(1)); runtime.Wake();
        await CelebrationTestClock.Until(() => Volatile.Read(ref triggered) == 2);
        await runtime.RetireAsync();
        Check(reads == 4, "Retirement cancels the next day's delayed work; an open client has no second baseline read");
        clock.Advance(TimeSpan.FromDays(-1));
        using var restarted = new ScmAchievementUnlockRuntime(root, () => (Owner, 1),
            (_, _) => { triggered++; return Task.CompletedTask; }, (_, _) => Task.FromResult(Catalog()), (_, _, _) => { }, clock);
        restarted.Wake(); await restarted.WaitForIdleAsync();
        Check(triggered == 2, "Restart and local clock rollback cannot repeat an already claimed date");
    }
    // Production passes no trusted start anchor (AccountBridgeRuntime), so this
    // is the path users take. Build 105, user 11-21: "成就庆祝的预期是用户可以明显的
    // 看到，不要在加载的时候就已经获取然后不弹庆祝了".
    private static async Task ProductionStartup(string root)
    {
        var clock = new CelebrationTestClock();
        var now = clock.GetUtcNow(); // A fixed mid-day SCM date, away from 16:00 UTC.
        clock.Advance(new DateTimeOffset(now.UtcDateTime.Date.AddDays(1).AddHours(2), TimeSpan.Zero) - now);
        var real = DateTimeOffset.UtcNow.AddMinutes(-1); // Stored unlock times must not be in the future.
        ScmAchievementItem At(int id) => Item(id, real, id);
        var catalog = Catalog(At(1)); var reads = 0; var triggered = 0; var acknowledge = true;
        var earned = new List<string>(); var summaries = new List<string[]>();
        ScmAchievementUnlockRuntime Create(Func<CancellationToken, Task<ScmAchievementCatalog>>? read = null) => new(root, () => (Owner, 1),
            (_, _) => { if (++triggered == 1) catalog = Catalog([.. catalog.Items, At(2)]); return Task.CompletedTask; },
            (_, token) => { Interlocked.Increment(ref reads); return read?.Invoke(token) ?? Task.FromResult(catalog); },
            (_, item, receipt) => { lock (earned) earned.Add(item.Id); if (acknowledge) Shown(root, Owner, receipt); }, clock,
            summary: (_, rest) => { lock (earned) summaries.Add(rest.Select(p => p.Item.Id).ToArray()); if (acknowledge) foreach (var p in rest) Shown(root, Owner, p.Receipt); });
        using (var runtime = Create())
        {
            runtime.Wake();
            await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
            Check(reads == 1 && triggered == 1 && earned.Count == 0, "A new account's first read is its silent baseline, taken before the trigger");
            clock.Advance(TimeSpan.FromSeconds(3));
            await CelebrationTestClock.Until(() => earned.Count == 1);
            await runtime.WaitForIdleAsync();
            Check(earned.Single() == "scm-2" && reads == 2, "What the daily trigger unlocks is celebrated without opening any page");
            clock.Advance(TimeSpan.FromMinutes(59)); runtime.Wake(); await runtime.WaitForIdleAsync();
            Check(reads == 2, "No reread inside the hour");
            catalog = Catalog([.. catalog.Items, At(3)]);
            clock.Advance(TimeSpan.FromMinutes(1)); runtime.Wake(); await runtime.WaitForIdleAsync();
            Check(reads == 3 && triggered == 1 && earned.Last() == "scm-3", "A client left open rereads hourly, without a trigger, and celebrates");
        }
        catalog = Catalog([.. catalog.Items, At(4)]);
        using (var restarted = Create())
        {
            restarted.Wake(); await restarted.WaitForIdleAsync();
            Check(reads == 4 && triggered == 1 && earned.Last() == "scm-4" && earned.Count(id => id == "scm-2") == 1,
                "After a restart the first read celebrates what unlocked while the client was closed, and nothing shown before");
            acknowledge = false; catalog = Catalog([.. catalog.Items, At(5)]);
            await restarted.ObserveAsync(Owner, 1, catalog);
            Check(earned.Last() == "scm-5" && Pending(root, Owner).Single().Item.Id == "scm-5", "A card handed over but not yet shown stays pending");
            await restarted.RetireAsync();
        }
        var delivered = earned.Count; var blockedReads = reads;
        using (var waiting = Create(async token => { await Task.Delay(Timeout.InfiniteTimeSpan, token); return catalog; }))
        {
            waiting.Wake();
            await CelebrationTestClock.Until(() => earned.Count == delivered + 1);
            Check(earned.Last() == "scm-5", "A new process hands stored, unshown cards over without waiting for SCM");
            await CelebrationTestClock.Until(() => reads == blockedReads + 1);
            await waiting.RetireAsync();
        }
        Shown(root, Owner, Pending(root, Owner).Single().Receipt); acknowledge = true;
        using (var batch = Create())
        {
            catalog = Catalog([.. catalog.Items, At(6), At(7), At(8), At(9), At(10), At(11)]);
            delivered = earned.Count;
            await batch.ObserveAsync(Owner, 1, catalog);
            Check(earned.Skip(delivered).SequenceEqual(new[] { "scm-6", "scm-7", "scm-8" }) && summaries.Single().SequenceEqual(new[] { "scm-9", "scm-10", "scm-11" }),
                "Six at once: three single cards, then one summary for the rest");
            catalog = Catalog([.. catalog.Items, At(12), At(13), At(14), At(15)]);
            delivered = earned.Count;
            await batch.ObserveAsync(Owner, 1, catalog);
            Check(earned.Skip(delivered).SequenceEqual(new[] { "scm-12", "scm-13", "scm-14", "scm-15" }) && summaries.Count == 1,
                "Four at once stay single cards; a summary of one would add nothing");
            Check(Pending(root, Owner).Length == 0, "Every shown card and summary is acknowledged");
            await batch.RetireAsync();
        }
        Console.WriteLine("PASS CX-ACHCEL SCM production startup: baseline before trigger, hourly reread, catch-up after restart, pending until shown, 3 + summary");
    }
    // R1 P1: a new account whose first read fails must not claim the day or
    // trigger, or the trigger's unlock would be absorbed by the first good read.
    private static async Task FailedBaselineRead(string root)
    {
        var clock = new CelebrationTestClock();
        var now = clock.GetUtcNow();
        clock.Advance(new DateTimeOffset(now.UtcDateTime.Date.AddDays(1).AddHours(2), TimeSpan.Zero) - now);
        var real = DateTimeOffset.UtcNow.AddMinutes(-1);
        ScmAchievementItem At(int id) => Item(id, real, id);
        var catalog = Catalog(At(1)); var fail = true; var reads = 0; var triggered = 0; var earned = new List<string>();
        (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
        using var runtime = new ScmAchievementUnlockRuntime(root, () => current,
            (_, _) => { if (++triggered == 1) catalog = Catalog([.. catalog.Items, At(2)]); return Task.CompletedTask; },
            (_, _) => { Interlocked.Increment(ref reads); return fail ? Task.FromException<ScmAchievementCatalog>(new HttpRequestException("synthetic")) : Task.FromResult(catalog); },
            (_, item, receipt) => { lock (earned) earned.Add(item.Id); Shown(root, current.Context!, receipt); }, clock);
        runtime.Wake(); await runtime.WaitForIdleAsync();
        Check(reads == 1 && triggered == 0, "A failed first read neither claims the day nor triggers");
        clock.Advance(TimeSpan.FromMinutes(14)); runtime.Wake(); await runtime.WaitForIdleAsync();
        Check(reads == 1, "A failed read waits 15 minutes before the next attempt (five-minute wakes do not hammer SCM)");
        fail = false; clock.Advance(TimeSpan.FromMinutes(1)); runtime.Wake();
        await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
        Check(reads == 2 && triggered == 1 && earned.Count == 0, "Once the first sync is stored, the same day is claimed and triggered");
        clock.Advance(TimeSpan.FromSeconds(3));
        await CelebrationTestClock.Until(() => earned.Count == 1); await runtime.WaitForIdleAsync();
        Check(earned.Single() == "scm-2", "The trigger's unlock is celebrated, not absorbed as history");
        var afterReads = reads;
        current = (Owner with { Subject = "synthetic-failed-baseline-other" }, 2); runtime.Invalidate(2);
        // B's own first sync; its rereads then wait on the test clock until A returns.
        await CelebrationTestClock.Until(() => reads == afterReads + 1 && triggered == 2);
        current = (Owner, 3); runtime.Invalidate(3);
        await Task.Delay(100); await runtime.WaitForIdleAsync();
        Check(reads == afterReads + 1, "A→B→A keeps A's read time; returning does not read again within the hour");
        Console.WriteLine("PASS R1 P1 FailedBaselineRead: no claim or trigger before a stored first sync, 15-minute retry, A→B→A schedule kept");
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
        var reading = false; var earned = 0; var triggered = 0;
        using var runtime = new ScmAchievementUnlockRuntime(root, () => current, (_, _) => { triggered++; return Task.CompletedTask; },
            (_, _) => { reading = true; return held.Task; }, (_, _, _) => earned++, clock, clock.GetUtcNow());
        // Build 105: the baseline read before the trigger is the read held here.
        runtime.Wake(); await CelebrationTestClock.Until(() => reading);
        current = (null, 2); runtime.Invalidate(2);
        held.SetResult(Catalog(Item(1, clock.GetUtcNow())));
        await runtime.WaitForIdleAsync();
        Check(earned == 0, "Late old-account read cannot celebrate after account switch");
        using (var lease = new ScmAchievementUnlockStore(root).Open(Owner))
            Check(triggered == 0 && lease.Read().TriggerDates.Length == 0,
                "R2: a switch during the first read neither claims the old account's day nor triggers");
    }
}
