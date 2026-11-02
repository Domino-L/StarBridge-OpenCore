namespace StarBridge.Desktop.Tests;

// Overlay open time for the app-stats heartbeat: counted while open, never across sleep
// or a stalled check. Synthetic timestamps only (1 tick = 1 ms).
internal static class OverlayUsageClockTests
{
    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL overlay usage: " + name);
        Console.WriteLine("PASS overlay usage: " + name);
    }

    internal static void Run()
    {
        // Ten minutes open, sampled every 750 ms like the game-window check.
        var clock = new OverlayUsageClock(1000);
        long t = 1;
        for (; t <= 600_000; t += 750) clock.Sample(true, t);
        var open = clock.TakeSeconds();
        Check(open is >= 599 and <= 600, $"ten minutes open counts about 600 s ({open})");
        Check(clock.TakeSeconds() == 0, "taken seconds are not counted twice");

        // An eight-hour sleep with the overlay open adds nothing; counting resumes after it.
        clock.Sample(true, t + 8L * 3600 * 1000);
        Check(clock.TakeSeconds() == 0, "an eight-hour gap is dropped whole");
        var resume = t + 8L * 3600 * 1000;
        for (var s = resume; s <= resume + 30_000; s += 750) clock.Sample(true, s);
        var after = clock.TakeSeconds();
        Check(after is >= 29 and <= 30, $"counting resumes after the gap ({after})");

        // Closed time never counts; a gap just over the 5 s limit is dropped, one under it is kept.
        var closed = new OverlayUsageClock(1000);
        for (long s = 1; s <= 60_000; s += 750) closed.Sample(false, s);
        Check(closed.TakeSeconds() == 0, "closed overlay counts nothing");
        var steps = new OverlayUsageClock(1000);
        steps.Sample(true, 1); steps.Sample(true, 4_901); steps.Sample(true, 10_002);
        Check(steps.TakeSeconds() == 4, "a 4.9 s step counts, a 5.1 s step is dropped");

        // Fractions carry over between heartbeats; opening counts from the next step.
        var carry = new OverlayUsageClock(1000);
        carry.Sample(false, 1); carry.Sample(true, 1_001); carry.Sample(true, 2_501);
        Check(carry.TakeSeconds() == 1 && carry.IsOpen, "1.5 s open reports 1 s, overlay open");
        carry.Sample(true, 3_001);
        Check(carry.TakeSeconds() == 1, "the 0.5 s remainder carries into the next report");
        carry.Sample(false, 3_500);
        Check(!carry.IsOpen, "closing is visible to the heartbeat");
    }
}
