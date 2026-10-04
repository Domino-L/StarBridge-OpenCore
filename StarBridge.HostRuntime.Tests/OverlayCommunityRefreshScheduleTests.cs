using System.Net;
using System.Threading.Channels;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayCommunityRefreshScheduleTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "schedule-fixture");
    private static readonly DateTimeOffset Start = new(2026, 9, 30, 0, 0, 0, TimeSpan.Zero);
    internal static async Task Run()
    {
        foreach (var error in new Exception[] {
            new OperationCanceledException(), new AccountBridgeHostException("communities.unavailable", true),
            new HttpRequestException("network"), new HttpRequestException("server", null, HttpStatusCode.ServiceUnavailable),
            new IOException("connection ended"), new TimeoutException("deadline") })
            await RecoverWithinOriginalLease(error);
        await TerminalAndStaleFailures();
        await SlowCommunicationReservesRosterRenewalTime();
    }

    private static async Task SlowCommunicationReservesRosterRenewalTime()
    {
        var now = Start;
        var waits = Channel.CreateUnbounded<Wait>();
        async Task Pause(TimeSpan delay, CancellationToken token)
        { var wait = new Wait(delay); waits.Writer.TryWrite(wait); await wait.Release.Task.WaitAsync(token); }
        async Task<Wait> Next() => await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        using var source = new OverlayCommunitySource(() => (Owner, 1), new SlowCommunicationReader(() => now += TimeSpan.FromSeconds(19)),
            true, () => now, waitForWake: Pause);
        source.ReadForDisplay();
        (await Next()).Release.SetResult();
        var scheduled = await Next();
        Check(source.Read() is not null, "slow enrichment still has a freshly accepted roster");
        Check(scheduled.Delay <= TimeSpan.FromSeconds(1),
            "19-second enrichment must not add another 15-second wait before a roster renewal which can take 20 seconds");
        source.Dispose();
        await source.Completion.WaitAsync(TimeSpan.FromSeconds(3));
    }
    private sealed class SlowCommunicationReader(Action finish) : IOverlayCommunityReader
    {
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Example", "target")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
            throw new InvalidOperationException("The progressive production seam must be used.");
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target,
            Action<InformationOverlayCommunityContent> rosterReady, CancellationToken token)
        { var content = new InformationOverlayCommunityContent("A", "Example", []); rosterReady(content); finish(); return Task.FromResult(content); }
    }

    private static async Task RecoverWithinOriginalLease(Exception failure)
    {
        var now = Start;
        var waits = Channel.CreateUnbounded<Wait>();
        async Task Pause(TimeSpan delay, CancellationToken token)
        {
            var wait = new Wait(delay);
            waits.Writer.TryWrite(wait);
            await wait.Release.Task.WaitAsync(token);
        }
        async Task<Wait> Next() => await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        OverlayCommunitySource? source = null;
        var reader = new Reader();
        reader.Read = () =>
        {
            if (reader.Reads == 2)
            {
                // The actual driver's second refresh starts at 15 seconds and
                // takes the existing 20-second deadline to fail. No wall sleep.
                now = now.AddSeconds(20);
                source!.ReadForDisplay();
                throw failure;
            }
            return Task.FromResult(new InformationOverlayCommunityContent("A", "Example", []));
        };
        using (source = new OverlayCommunitySource(() => (Owner, 1), reader, true, () => now, waitForWake: Pause))
        {
            source.ReadForDisplay();
            (await Next()).Release.SetResult();
            var healthyWait = await Next();
            var first = source.Read();
            Check(first is not null && reader.Reads == 1, "initial authorized snapshot exists");
            Check(healthyWait.Delay == TimeSpan.FromSeconds(15), "healthy polling remains unchanged");
            now += healthyWait.Delay;
            source.ReadForDisplay();
            healthyWait.Release.SetResult();
            var retry = await Next();
            Check(ReferenceEquals(first, source.Read()), $"{failure.GetType().Name}: transient transport must not clear unexpired authorized content");
            Check(retry.Delay <= TimeSpan.FromSeconds(1),
                $"{failure.GetType().Name}: timeout at t=35 must retry before the original t=40 expiry; actual delay={retry.Delay.TotalSeconds}s");
            now += retry.Delay;
            source.ReadForDisplay();
            retry.Release.SetResult();
            var healthyAfterRecovery = await Next();
            Check(reader.Reads == 3 && source.Read() is not null && now < Start.AddSeconds(40),
                "driver recovers within the original lease without a null display frame");
            Check(source.Read()!.ContinuityId == first!.ContinuityId,
                "same-source recovery inside the lease must not make Native clear the whole authorized display");
            var lastSuccess = now;
            Check(healthyAfterRecovery.Delay == TimeSpan.FromSeconds(15), "success restores normal cadence");
            reader.Read = () => throw failure;
            var currentWait = healthyAfterRecovery;
            foreach (var seconds in new[] { 1, 3, 5, 15 })
            {
                now += currentWait.Delay;
                source.ReadForDisplay();
                currentWait.Release.SetResult();
                currentWait = await Next();
                Check(currentWait.Delay == TimeSpan.FromSeconds(seconds), "repeated failures use bounded backoff, not a hot loop");
            }
            now = lastSuccess.AddSeconds(40);
            Check(source.Read() is null, "retries never extend the last success lease at the exact expiry");
            var readsBeforeClosing = reader.Reads;
            now += TimeSpan.FromSeconds(21);
            currentWait.Release.SetResult();
            var standby = await Next();
            Check(reader.Reads == readsBeforeClosing && standby.Delay == TimeSpan.FromSeconds(15),
                "closed overlays stop retry reads and reset fast wakeups to standby cadence");
            source.Dispose();
            await source.Completion.WaitAsync(TimeSpan.FromSeconds(3));
        }
    }

    private static async Task TerminalAndStaleFailures()
    {
        var reader = new Reader();
        InformationOverlayCommunityContent Content() => new("A", "Example", []);
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        foreach (var terminal in new Exception[] {
            new AccountBridgeHostException("communities.forbidden"),
            new HttpRequestException("forbidden", null, HttpStatusCode.Forbidden),
            new HttpRequestException("unauthorized", null, HttpStatusCode.Unauthorized),
            new InvalidDataException("schema"), new System.Text.Json.JsonException("malformed"),
            new InvalidOperationException("unclassified") })
        {
            reader.Read = () => Task.FromResult(Content());
            await source.RefreshAsync();
            Check(source.Read() is not null, "fixture has an unexpired authorized source");
            reader.Read = () => throw terminal;
            await source.RefreshAsync();
            Check(source.Read() is null, $"{terminal.GetType().Name} revokes immediately, without retry retention");
        }
        reader.Read = () => Task.FromResult(Content());
        await source.RefreshAsync();
        var pending = new TaskCompletionSource<InformationOverlayCommunityContent>(TaskCreationOptions.RunContinuationsAsynchronously);
        reader.Read = () => pending.Task;
        var oldRefresh = source.RefreshAsync();
        source.Rename(Owner, 1, "A", "New authorized name");
        pending.SetException(new InvalidDataException("old revision failed"));
        await oldRefresh;
        Check(source.Read()?.Name == "New authorized name", "a failed old revision cannot clear the newer authorized display");
    }

    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
    private sealed class Wait(TimeSpan delay)
    {
        internal TimeSpan Delay = delay;
        internal TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }
    private sealed class Reader : IOverlayCommunityReader
    {
        internal int Reads;
        internal Func<Task<InformationOverlayCommunityContent>> Read = null!;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Example", "target")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        { Reads++; return Read(); }
    }
}
