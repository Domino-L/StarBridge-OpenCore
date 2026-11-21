using System.Collections.Concurrent;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class VisitorGameplayTimeTests
{
    private static readonly BridgeAccountContext Owner = new("test", "oauth.invalid", "test-visitor-owner");
    private static readonly BridgeAccountContext Other = new("test", "oauth.invalid", "test-visitor-other");

    internal static async Task Run()
    {
        (string Name, Func<Task> Verify)[] cases =
        [
            ("G1/G2 Japan authority, deduplication and reset", AuthorityAndReset),
            ("G3 with no Japanese pair, failed reads and a missing adapter send nothing (contract af70120d)", LocalFallback),
            ("G3c an adapter reporting gameplay.reset_unsupported never sends this PC's total", UnsupportedSendsNothing),
            ("G4 last snapshot in the debounce window", Debounce),
            ("G4b a trigger after the deadline but before the timer keeps the first deadline", DeadlineRace),
            ("G6b a changing total keeps the retry level and Retry-After", RetryWithChangingTotal),
            ("G6c a value queued during the last retry waits for the next trigger", SpentCycleDropsQueued),
            ("G3b a failed read sends the account total the owner still sees", ShownAccountTotalFallback),
            ("G5 unavailable retries on trigger, invalid is suppressed and redacted", UnavailableAndInvalid),
            ("G6 Retry-After and three bounded retries", Retry),
            ("G7 stale revision waits for fresh authority", StaleRevision),
            ("G8 Japan and local recording proceed during a failed HK write", Independent),
            ("G9 legacy login never calls HK", Legacy),
            ("G10 account and generation cancel pending, retry and in-flight work", AccountChange),
            ("G11 new scoped receipt only, with byte-identical legacy data", Receipt),
            ("G12 HTTP contract and guarded OAuth authorization", VisitorGameplayTimeTransportTests.Run),
        ];
        foreach (var (name, verify) in cases)
        {
            await verify();
            Console.WriteLine("PASS visitor gameplay time " + name);
        }
    }

    private static async Task AuthorityAndReset()
    {
        using var f = new Fixture();
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.SequenceEqual([new(3600, 7)]) && f.Japan.Publications == 0, "initial authority");
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.Count == 1, "same pair skipped");
        f.Japan.State = new(1, 8, Guid.NewGuid().ToString("N"), 7, 0, 0, null, IsPublic: true);
        await f.Runtime.RecoverResetAsync(f.Japan);
        await f.Clock.Advance(30);
        Require(f.Hk.Values.SequenceEqual([new(3600, 7), new(0, 8)]) &&
            f.LocalSeconds() == 0 && f.Japan.Publications == 0, "reset authority can lower total");
    }

    private static async Task LocalFallback()
    {
        foreach (var viaRecovery in new[] { false, true })
        foreach (var unsupported in new[] { true, false })
        {
            using var f = new Fixture(1200, imported: true);
            f.Japan.ReadError = unsupported ? new GameplayTimeException("gameplay.reset_unsupported") : new IOException();
            var displayed = f.LocalSeconds();
            if (viaRecovery) await f.Runtime.RecoverResetAsync(f.Japan);
            else await f.Tick();
            await f.Clock.Advance(30);
            // Contract af70120d: with no Japanese pair, 104 sends nothing (SCM-only accounts wait for 0.7.4).
            Require(displayed == 1200 && f.Japan.Reads == 1 && f.Japan.Publications == 0 && f.Hk.Values.Count == 0,
                "no local total without a Japanese pair (recovery=" + viaRecovery + ", unsupported=" + unsupported + ")");
        }
        using var withoutJapan = new Fixture(180, hasJapan: false);
        await withoutJapan.Tick();
        await withoutJapan.Clock.Advance(30);
        Require(withoutJapan.Hk.Values.Count == 0, "no Japanese adapter sends nothing in 104");
    }

    private static async Task UnsupportedSendsNothing()
    {
        // (b) The Host's own adapter throws gameplay.reset_unsupported (no legacy login client, or a context
        // mismatch while the account switches). A linked account without a Japanese pair must not send this
        // PC's total without a revision, whether the throw comes from a publication tick or reset recovery,
        // and however long it lasts.
        foreach (var viaRecovery in new[] { false, true })
        {
            using var f = new Fixture(5000);
            f.Japan.ReadError = new GameplayTimeException("gameplay.reset_unsupported");
            for (var round = 0; round < 3; round++)
            {
                if (viaRecovery) await f.Runtime.RecoverResetAsync(f.Japan);
                else await f.Tick();
                await f.Clock.Advance(30);
            }
            Require(f.LocalSeconds() == 5000 && f.Hk.Values.Count == 0,
                "unsupported never sends the local 5000 s (recovery=" + viaRecovery + ")");
        }
    }

    private static async Task Debounce()
    {
        using var f = new Fixture();
        await f.Tick();
        await f.Clock.Advance(10);
        f.Japan.State = f.Japan.State with { PlayTimeSeconds = 3700, Revision = 8 };
        await f.Tick();
        await f.Clock.Advance(10);
        f.Japan.State = f.Japan.State with { PlayTimeSeconds = 3800, Revision = 9 };
        await f.Tick();
        await f.Clock.Advance(9);
        Require(f.Hk.Values.Count == 0, "the window is still open");
        await f.Clock.Advance(1);
        Require(f.Hk.Values.SequenceEqual([new(3800, 9)]), "only the final pair reached HK, at the first deadline");
    }

    private static async Task DeadlineRace()
    {
        using var f = new Fixture();
        await f.Tick();
        f.Clock.Shift(30);
        f.Japan.State = f.Japan.State with { PlayTimeSeconds = 3700, Revision = 8 };
        await f.Tick();
        await f.Clock.Advance(0);
        Require(f.Hk.Values.SequenceEqual([new(3700, 8)]), "the late trigger is sent at the first deadline, not 30 s later");
    }

    private static async Task RetryWithChangingTotal()
    {
        using var f = new Fixture();
        f.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.TemporaryFailure));
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.Count == 1, "first attempt");
        var seconds = 3600;
        foreach (var wait in new[] { 60, 300, 1800 })
        {
            var count = f.Hk.Values.Count;
            // A new total arrives every 30 s during the wait, as while playing.
            for (var elapsed = 30; elapsed < wait; elapsed += 30)
            {
                seconds += 30;
                f.Japan.State = f.Japan.State with { PlayTimeSeconds = seconds };
                await f.Tick();
                await f.Clock.Advance(30);
                Require(f.Hk.Values.Count == count, "a changed total must not restart the backoff at one minute");
            }
            // The loop advanced the whole wait except its last 30 s.
            await f.Clock.Advance(wait - ((wait - 1) / 30) * 30);
            Require(f.Hk.Values.Count == count + 1, "retry at the original level");
            Require(f.Hk.Values[^1].Seconds == seconds, "the retry carries the latest total");
        }
        await f.Clock.Advance(3600);
        Require(f.Hk.Values.Count == 4, "the cycle still stops after three retries");
    }

    private static async Task SpentCycleDropsQueued()
    {
        using var f = new Fixture();
        var last = new TaskCompletionSource<VisitorGameplayTimeResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var attempts = 0;
        f.Hk.Reply = _ => ++attempts < 4
            ? Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.TemporaryFailure))
            : last.Task;
        await f.Tick();
        await f.Clock.Advance(30);
        await f.Clock.Advance(60);
        await f.Clock.Advance(300);
        _ = f.Clock.StartAdvance(1800);
        for (var i = 0; i < 100 && f.Hk.Values.Count < 4; i++) await Task.Delay(10);
        Require(f.Hk.Values.Count == 4, "the third retry is in flight");
        f.Japan.State = f.Japan.State with { PlayTimeSeconds = 3900, Revision = 8 };
        await f.Tick();
        last.SetResult(new(VisitorGameplayTimeOutcome.TemporaryFailure));
        for (var i = 0; i < 20; i++) await Task.Delay(10);
        await f.Clock.Advance(60);
        Require(f.Hk.Values.Count == 4, "the value queued during the last retry did not start a new cycle by itself");
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.Count == 5 && f.Hk.Values[^1] == new VisitorGameplayTime(3900, 8),
            "the next trigger starts a new cycle with the latest total");
    }

    private static async Task ShownAccountTotalFallback()
    {
        using var f = new Fixture(1200);
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.SequenceEqual([new(3600, 7)]), "authority first");
        f.Japan.ReadError = new IOException();
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.SequenceEqual([new(3600, 7)]),
            "a failed read re-offers Japan's last pair with its revision (already on HK), never a revision-less copy");

        // The pair from before the outage still carries its revision when HK had not taken it yet, so a newer
        // reset that another device wrote (revision 8) wins on HK with a 409 instead of being overwritten.
        using var g = new Fixture(1200);
        g.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.Unavailable));
        await g.Tick();
        await g.Clock.Advance(30);
        g.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.Ok));
        g.Japan.ReadError = new IOException();
        await g.Tick();
        await g.Clock.Advance(30);
        Require(g.Hk.Values.SequenceEqual([new(3600, 7), new(3600, 7)]),
            "the outage resend keeps revision 7 and never falls back to this PC's 1200 s");
    }

    private static async Task UnavailableAndInvalid()
    {
        using var f = new Fixture();
        var messages = new ConcurrentQueue<string>();
        using var capture = IdentityGateJournal.Capture((stage, line) =>
        {
            if (stage == "gameplay-time-hk") messages.Enqueue(line);
        });
        f.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.Unavailable));
        await f.Tick();
        await f.Clock.Advance(30);
        await f.Clock.Advance(60);
        Require(f.Hk.Values.Count == 1 && messages.IsEmpty, "404 stays quiet without automatic retry");
        f.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.Invalid, Field: "playTimeSeconds"));
        await f.Tick();
        await f.Clock.Advance(30);
        f.Japan.State = f.Japan.State with { Revision = 8 };
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.Count == 2 && messages.SequenceEqual(["code=gameplay_time.invalid field=playTimeSeconds"]),
            "400 logs only safe metadata and suppresses the same seconds");
    }

    private static async Task Retry()
    {
        using var f = new Fixture();
        f.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.TemporaryFailure,
            RetryAfter: TimeSpan.FromSeconds(120)));
        await f.Tick();
        await f.Clock.Advance(30);
        await f.Tick();
        await f.Clock.Advance(119);
        Require(f.Hk.Values.Count == 1, "Retry-After holds even across a regular publication trigger");
        await f.Clock.Advance(1);
        Require(f.Hk.Values.Count == 2, "Retry-After elapsed");
        await f.Clock.Advance(299);
        Require(f.Hk.Values.Count == 2, "the five-minute backoff is longer than Retry-After");
        await f.Clock.Advance(1);
        Require(f.Hk.Values.Count == 3, "the longer backoff elapsed");

        using var failing = new Fixture();
        failing.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.TemporaryFailure));
        await failing.Tick();
        await failing.Clock.Advance(30);
        foreach (var wait in new[] { 60, 300, 1800 })
        {
            var count = failing.Hk.Values.Count;
            await failing.Clock.Advance(wait - 1);
            Require(failing.Hk.Values.Count == count, "retry fired early");
            await failing.Clock.Advance(1);
            Require(failing.Hk.Values.Count == count + 1, "retry was not sent");
        }
        await failing.Clock.Advance(3600);
        Require(failing.Hk.Values.Count == 4, "no fourth retry after the initial request");
        await failing.Tick();
        await failing.Clock.Advance(30);
        Require(failing.Hk.Values.Count == 5, "next trigger may try again");
    }

    private static async Task StaleRevision()
    {
        using var f = new Fixture();
        f.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.StaleRevision, StoredRevision: 8));
        await f.Tick();
        await f.Clock.Advance(30);
        await f.Tick();
        await f.Clock.Advance(30);
        f.Japan.State = f.Japan.State with { PlayTimeSeconds = 3601 };
        await f.Tick();
        await f.Clock.Advance(30);
        f.Japan.ReadError = new IOException();
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.Count == 1, "409 is neither replayed nor bypassed with an unversioned value");
        f.Japan.ReadError = null;
        f.Japan.State = f.Japan.State with { PlayTimeSeconds = 3600, Revision = 8 };
        f.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.Ok));
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.SequenceEqual([new(3600, 7), new(3600, 8)]), "new authority is admitted");
    }

    private static async Task Independent()
    {
        using var f = new Fixture(4000);
        var started = Signal();
        var release = Signal();
        f.Hk.Reply = async token =>
        {
            started.TrySetResult();
            await release.Task.WaitAsync(token);
            throw new HttpRequestException("synthetic write failure");
        };
        await f.Tick();
        Require(f.Japan.LastUpdate?.PlayTimeSeconds == 4000 && f.Hk.Values.Count == 0, "Japan sends before HK debounce");
        var completion = f.Clock.StartAdvance(30);
        await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        try
        {
            f.Runtime.Sample();
            _ = f.Clock.StartAdvance(5);
            f.Runtime.Sample();
            await f.Tick().WaitAsync(TimeSpan.FromSeconds(2));
            Require(f.Japan.Publications == 2 && f.LocalSeconds() == 4005 &&
                // R4: HK gets this round's GET pair; the PUT acknowledgement carries no revision, so the written
                // 4000 s reach HK with the next GET that reports them under their own revision.
                f.Hk.Values.SequenceEqual([new(3600, 7)]), "HK uses the GET pair and cannot block Japan or recording");
        }
        finally { release.TrySetResult(); }
        await completion.WaitAsync(TimeSpan.FromSeconds(5));

        using var rejected = new Fixture(4000);
        rejected.Japan.Accept = false;
        await rejected.Tick();
        await rejected.Clock.Advance(30);
        Require(rejected.Japan.Publications == 1 && rejected.Hk.Values.SequenceEqual([new(3600, 7)]),
            "failed Japan PUT leaves the observed value authoritative");
    }

    private static async Task Legacy()
    {
        using var f = new Fixture();
        f.Hk.Scm = false;
        await f.Tick();
        await f.Clock.Advance(60);
        Require(f.Japan.Reads == 1 && f.Hk.Values.Count == 0 && f.Clock.TimerCount == 0, "legacy login has no HK work");
    }

    private static async Task AccountChange()
    {
        using var f = new Fixture();
        await f.Tick();
        f.Current = (Other, 2);
        f.Runtime.Suspend();
        await f.Clock.Advance(60);
        Require(f.Hk.Values.Count == 0, "old pending write dropped on switch");

        f.Hk.Reply = _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.TemporaryFailure));
        await f.Tick();
        await f.Clock.Advance(30);
        f.Current = (Other, 3);
        f.Runtime.Suspend();
        await f.Clock.Advance(120);
        Require(f.Hk.Calls.SequenceEqual([(Other, 2L, new VisitorGameplayTime(3600, 7))]), "same account new generation drops retry");

        var started = Signal();
        var cancelled = Signal();
        f.Hk.Reply = async token =>
        {
            started.TrySetResult();
            try { await Task.Delay(Timeout.InfiniteTimeSpan, token); }
            catch (OperationCanceledException) { cancelled.TrySetResult(); throw; }
            throw new InvalidOperationException("Expected cancellation.");
        };
        await f.Tick();
        _ = f.Clock.StartAdvance(30);
        await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        f.Current = (null, 4);
        f.Runtime.Suspend();
        await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await f.Clock.Advance(3600);
        Require(f.Hk.Values.Count == 2 && !Directory.Exists(Path.Combine(f.Root, "gameplay-time-hk-v1")),
            "sign-out cancels the in-flight attempt without a receipt or retry");
    }

    private static async Task Receipt()
    {
        using var f = new Fixture(1000);
        var directory = Path.Combine(f.Root, "gameplay-time-local-v1");
        var legacy = Directory.GetFiles(directory).ToDictionary(p => p, File.ReadAllBytes);
        await f.Tick();
        await f.Clock.Advance(30);
        var receipt = Directory.GetFiles(Path.Combine(f.Root, "gameplay-time-hk-v1"), "*", SearchOption.AllDirectories).Single();
        using var json = JsonDocument.Parse(File.ReadAllText(receipt));
        var body = json.RootElement;
        Require(body.EnumerateObject().Select(field => field.Name).Order().SequenceEqual(["accountScope", "seconds", "sourceRevision"]) &&
            body.GetProperty("seconds").GetInt64() == 3600 && body.GetProperty("sourceRevision").GetInt64() == 7 &&
            body.GetProperty("accountScope").GetString() == Path.GetFileName(Path.GetDirectoryName(receipt)),
            "receipt contains only the acknowledged pair and a hashed account scope");
        f.Runtime.Dispose();
        Require(Directory.GetFiles(directory).Order().SequenceEqual(legacy.Keys.Order()) &&
            legacy.All(file => File.ReadAllBytes(file.Key).SequenceEqual(file.Value)), "old storage stays byte-identical");
        f.RestartRuntime();
        await f.Tick();
        await f.Clock.Advance(30);
        Require(f.Hk.Values.Count == 1 && new VisitorGameplayTimeReceiptStore(f.Root).Read(Other) is null,
            "restart deduplicates and another account cannot read the receipt");
    }

    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("Visitor gameplay time: " + message);
    }

    private sealed class Fixture : IDisposable
    {
        private readonly GameplayTimeStore _store;
        private readonly bool _hasJapan;
        internal readonly string Root = Directory.CreateTempSubdirectory("visitor-gameplay-").FullName;
        internal readonly Clock Clock = new();
        internal readonly JapanRemote Japan = new();
        internal readonly HkRemote Hk = new();
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal GameplayTimeRuntime Runtime;

        internal Fixture(long seconds = 0, bool imported = false, bool hasJapan = true)
        {
            _store = new(Root);
            _hasJapan = hasJapan;
            using (var lease = _store.Open(Owner))
            {
                var previous = lease.Read();
                _ = lease.Save(previous, previous with
                {
                    Consent = GameplayRecordingConsent.Allowed,
                    Seconds = seconds,
                    ShowOnProfile = true,
                    HistoricalSeconds = imported ? seconds - 200 : null,
                    HistoryImportedAt = imported ? Clock.GetUtcNow() : null,
                }, () => true);
            }
            Runtime = Open();
        }

        private GameplayTimeRuntime Open() => new(_store, () => Current, presence: () => new(1, "running"),
            time: Clock, startTimer: false, historyRemote: _hasJapan ? Japan : null, visitorGameplayTimeRemote: Hk);
        internal Task Tick() => Runtime.PublishCurrentGameplayAsync();
        internal long LocalSeconds() => Runtime.Dispatch(BridgeEnvelope.Request("gameplayTime.read",
            "test-visitor-gameplay", Current.Generation, new { schemaVersion = 1 }, Current.Context))
            .Response.Payload.GetProperty("seconds").GetInt64();
        internal void RestartRuntime()
        {
            Runtime.Dispose();
            Runtime = Open();
        }
        public void Dispose()
        {
            Runtime.Dispose();
            Directory.Delete(Root, recursive: true);
        }
    }

    private sealed class JapanRemote : IGameplayHistoryRemote
    {
        internal GameplayTimeResetState State = new(1, 7, null, null, 3600, 0, null, IsPublic: true);
        internal Exception? ReadError;
        internal bool Accept = true;
        internal int Reads, Publications;
        internal PersonalProfileGameplayStatisticsUpdateRequestContract? LastUpdate;
        public Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken token)
        {
            Reads++;
            return ReadError is { } error ? Task.FromException<GameplayTimeResetState>(error) : Task.FromResult(State);
        }
        public Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner, GameplayTimeResetRequest request, CancellationToken token) =>
            throw new InvalidOperationException("No reset POST in these cases.");
        public Task<bool> PublishGameplayStatisticsAsync(BridgeAccountContext owner,
            PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token)
        {
            Publications++;
            LastUpdate = update;
            return Task.FromResult(Accept);
        }
    }

    private sealed class HkRemote : IVisitorGameplayTimeRemote
    {
        internal bool Scm = true;
        internal Func<CancellationToken, Task<VisitorGameplayTimeResult>> Reply =
            _ => Task.FromResult(new VisitorGameplayTimeResult(VisitorGameplayTimeOutcome.Ok));
        internal readonly ConcurrentQueue<(BridgeAccountContext Owner, long Generation, VisitorGameplayTime Value)> Calls = new();
        internal IReadOnlyList<VisitorGameplayTime> Values => Calls.Select(c => c.Value).ToArray();
        public bool Supports(BridgeAccountContext owner, long generation) => Scm;
        public Task<VisitorGameplayTimeResult> WriteAsync(BridgeAccountContext owner, long generation,
            VisitorGameplayTime value, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            Calls.Enqueue((owner, generation, value));
            return Reply(token);
        }
    }

    private sealed class Clock : TimeProvider
    {
        private long _ticks = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero).Ticks;
        private ManualTimer? _timer;
        internal int TimerCount { get; private set; }
        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref _ticks), TimeSpan.Zero);
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            TimerCount++;
            _timer = new(this, () => callback(state));
            _timer.Change(dueTime, period);
            return _timer;
        }
        internal Task Advance(int seconds) => StartAdvance(seconds).WaitAsync(TimeSpan.FromSeconds(5));
        // Moves time without running a due timer, as when a callback is late.
        internal void Shift(int seconds) => Interlocked.Add(ref _ticks, TimeSpan.FromSeconds(seconds).Ticks);
        internal Task StartAdvance(int seconds)
        {
            Interlocked.Add(ref _ticks, TimeSpan.FromSeconds(seconds).Ticks);
            return _timer?.FireIfDue() ?? Task.CompletedTask;
        }

        private sealed class ManualTimer(Clock clock, Action callback) : ITimer
        {
            private readonly object _gate = new();
            private DateTimeOffset? _due;
            private TaskCompletionSource _changed = Signal();
            public bool Change(TimeSpan due, TimeSpan period)
            {
                lock (_gate)
                {
                    _due = due == Timeout.InfiniteTimeSpan ? null : clock.GetUtcNow() + due;
                    _changed.TrySetResult();
                    _changed = Signal();
                }
                return true;
            }
            internal Task FireIfDue()
            {
                Task changed;
                lock (_gate)
                {
                    if (_due is not { } due || due > clock.GetUtcNow()) return Task.CompletedTask;
                    _due = null;
                    changed = _changed.Task;
                }
                callback();
                return changed;
            }
            public void Dispose() => Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }
}
