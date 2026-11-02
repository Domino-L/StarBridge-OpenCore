using StarBridge.HostRuntime.Achievements;
using System.IO;
using StarBridge.OverlayRuntime.Windows;

internal static class AchievementCelebrationPlaybackTests
{
    private sealed class Surface : IAchievementCelebrationSurface
    {
        public double LifetimeMilliseconds => 5980;
        public bool IsVisible { get; private set; }
        internal double Elapsed;
        internal bool Disposed;
        internal bool FailShow;
        internal bool FailDispose;
        internal int Remaining;
        public void Show() { if (FailShow) throw new InvalidOperationException("Synthetic show race"); IsVisible = true; }
        public void Hide() => IsVisible = false;
        public void Advance(double elapsed, int remaining) { Elapsed = elapsed; Remaining = remaining; }
        public void UpdatePosition() { }
        public void Dispose() { Disposed = true; Hide(); if (FailDispose) throw new IOException("Synthetic dispose failure"); }
    }
    internal static void Run()
    {
        var current = true; var allowed = true; var calls = 0; var plays = 0; var stops = 0;
        var surfaces = new List<Surface>();
        using var playback = new AchievementCelebrationPlayback(_ =>
        {
            calls++;
            var surface = new Surface(); surfaces.Add(surface);
            if (calls == 1) allowed = false; // Windows switched desktops during hidden HWND creation.
            return surface;
        }, () => allowed, check => { if (!check()) return false; plays++; return true; }, () => stops++);
        var notice = new AchievementCelebration("first-entry", DateTimeOffset.UnixEpoch.AddDays(1), 1, () => current);
        playback.Submit(notice); playback.Advance(250);
        Require(!playback.HasActive && surfaces[0].Disposed && plays == 0,
            "Desktop transition before show disposes the hidden surface and emits no sound");
        allowed = true; playback.Advance(250);
        Require(calls == 2 && playback.HasActive && plays == 1,
            "A desktop race retains the earned notice for unlock instead of dropping it");
        playback.Advance(600);
        allowed = false; playback.Advance(16);
        Require(!surfaces[1].IsVisible && stops == 1, "Lock hides the card and stops its soundtrack");
        playback.Advance(100000);
        allowed = true; playback.Advance(250);
        Require(surfaces[1].IsVisible && surfaces[1].Elapsed == 0 && plays == 2,
            "An interrupted entrance restarts the same presentation with its full soundtrack");
        for (var i = 0; i < 20; i++) playback.Advance(100); // Beyond the complete 1.65-second sound.
        allowed = false; playback.Advance(16);
        allowed = true; playback.Advance(250);
        Require(surfaces[1].Elapsed == 2000 && plays == 2,
            "Unlock during the readable hold preserves remaining time without replaying completed sound");
        playback.Advance(100000); // A sleeping or stalled dispatcher must not consume the entire hold.
        Require(playback.HasActive && surfaces[1].Elapsed == 2000,
            "Long scheduling gaps do not silently expire the achievement");
        playback.Advance(16);
        current = false; playback.Advance(16);
        Require(!playback.HasActive && surfaces[1].Disposed, "Account expiry clears presentation even when desktop is blocked");
        SerialAndFailure();
        SeriesQueue();
        FailureOwnership();
        Placement();
        Console.WriteLine("PASS achievement playback: desktop race, locked entrance/hold, suspend and account expiry");
    }
    private static void FailureOwnership()
    {
        var activity = new AchievementCelebrationActivity();
        var current = true; var failCreate = true; var stops = 0;
        var notice = new AchievementCelebration("first-entry", DateTimeOffset.UnixEpoch.AddDays(1), 1, () => current);
        var surfaces = new List<Surface>();
        using var playback = new AchievementCelebrationPlayback(_ => {
            if (failCreate) return null;
            var surface = new Surface { FailDispose = true }; surfaces.Add(surface); return surface;
        }, () => true, check => check(), () => { stops++; throw new IOException("Synthetic stop failure"); }, activity);
        playback.Submit(notice with { Receipt = "synthetic-retry-receipt" });
        playback.Submit(notice with { Receipt = "synthetic-retry-receipt" });
        for (var i = 0; i < 8; i++) playback.Advance(250);
        Require(!activity.IsActive && !playback.HasActive, "Persistent create failure releases Activity while retaining the receipt");
        failCreate = false; playback.Advance(250);
        Require(activity.IsActive && playback.HasActive && surfaces[0].Remaining == 0, "Successful retry reacquires Activity and deduplicates its receipt");
        playback.Clear();
        Require(!activity.IsActive && !playback.HasActive && stops == 1 && surfaces[0].Disposed,
            "Clear isolates dispose and stop failures and always releases Activity");
        playback.Submit(notice); playback.Advance(250); current = false; playback.Advance(16);
        Require(!activity.IsActive && !playback.HasActive && stops == 2, "Account invalidation releases Activity despite failing cleanup");
        current = true; playback.Submit(notice); playback.Advance(250); playback.Dispose();
        Require(!activity.IsActive && !playback.HasActive && stops == 3, "Dispose always releases Activity despite both cleanup failures");
        Console.WriteLine("PASS R3 FailureOwnership: persistent create failure, cleanup faults, account invalidation");
    }
    private static void SeriesQueue()
    {
        var current = true;
        var activity = new AchievementCelebrationActivity();
        var transitions = new List<bool>(); activity.Changed += transitions.Add;
        var notices = new List<AchievementCelebration>();
        var surfaces = new List<Surface>();
        using var playback = new AchievementCelebrationPlayback(notice =>
        {
            notices.Add(notice); var surface = new Surface(); surfaces.Add(surface); return surface;
        }, () => true, check => check(), () => { }, activity);
        var first = new AchievementCelebration("hangar-home", DateTimeOffset.UnixEpoch.AddDays(1), 1, () => current, 1);
        playback.Submit(first);
        playback.Submit(first with { Rank = 2 });
        playback.Submit(first with { AchievementId = "hangar-paths", Rank = 1 });
        playback.Advance(100);
        Require(notices.Count == 1 && notices[0].Rank == 1 && surfaces[0].Remaining == 2,
            "Every earned rank retains its own complete celebration");
        for (var i = 0; i < 60; i++) playback.Advance(100);
        playback.Advance(200);
        Require(notices.Count == 1 && activity.IsActive && transitions.SequenceEqual(new[] { true }), "Multiple series retain the protected inter-card pause");
        playback.Advance(20);
        Require(notices.Count == 2 && notices[1].AchievementId == "hangar-home" && notices[1].Rank == 2 && surfaces[1].Remaining == 1,
            "Separate series start in receipt order after a complete card");
        for (var i = 0; i < 60; i++) playback.Advance(100);
        playback.Advance(220);
        Require(notices.Count == 3 && notices[2].AchievementId == "hangar-paths" && notices[2].Rank == 1,
            "The third series is displayed without losing its rank");
        for (var i = 0; i < 60; i++) playback.Advance(100);
        Require(!playback.HasActive && surfaces.All(s => s.Disposed && s.Elapsed >= s.LifetimeMilliseconds) && !activity.IsActive &&
            transitions.SequenceEqual(new[] { true, false }), "All three achievements finish their full dwell without an unprotected gap");
        playback.Submit(first); current = false; playback.Advance(100);
        Require(!playback.HasActive && !activity.IsActive, "Expired pending receipts release presentation ownership");
    }
    private static void SerialAndFailure()
    {
        var current = true; var calls = 0; var plays = 0;
        var surfaces = new List<Surface>();
        using var playback = new AchievementCelebrationPlayback(_ =>
        {
            var surface = new Surface { FailShow = calls++ == 0 }; surfaces.Add(surface); return surface;
        }, () => true, check => { if (!check()) return false; plays++; return true; }, () => { });
        var first = new AchievementCelebration("first-entry", DateTimeOffset.UnixEpoch.AddDays(1), 1, () => current);
        playback.Submit(first);
        playback.Submit(first with { EarnedAt = first.EarnedAt.AddSeconds(1) });
        playback.Advance(250);
        Require(!playback.HasActive && surfaces[0].Disposed && plays == 0, "Failed show retains receipts without sounding");
        playback.Advance(250);
        Require(playback.HasActive && plays == 1 && surfaces[1].Remaining == 1,
            "Retry consumes exactly one notice, without duplicating the failed head");
        for (var i = 0; i < 60; i++) playback.Advance(100);
        Require(!playback.HasActive && surfaces[1].Disposed && plays == 1, "Full card completes before the next presentation");
        playback.Advance(200);
        Require(!playback.HasActive && plays == 1, "Serial queue preserves its 220ms inter-card breath");
        playback.Advance(20);
        Require(playback.HasActive && plays == 2 && surfaces[2].Remaining == 0, "Next queued notice starts once, after the gap");
        current = false; playback.Advance(100);
        playback.Clear(); playback.Dispose(); playback.Submit(first); playback.Advance(100);
        Require(!playback.HasActive && plays == 2, "Clear/dispose never resurrect expired notices");
    }
    private static void Placement()
    {
        foreach (var work in new[] {
            new System.Drawing.Rectangle(0, 0, 1920, 1040),
            new System.Drawing.Rectangle(-2560, -180, 2560, 1392),
            new System.Drawing.Rectangle(1920, 120, 800, 480) })
        foreach (var dpi in new uint[] { 96, 120, 144, 192, 288 })
        {
            var placement = AchievementCelebrationPlacement.ForWorkArea(work, dpi);
            Require(work.Contains(placement.Bounds) && placement.Margin == 0 && placement.Bounds.Right == work.Right &&
                placement.Bounds.Bottom == work.Bottom,
                "Every DPI and negative-coordinate monitor anchors the whole card within its work area");
        }
        var standard = AchievementCelebrationPlacement.ForWorkArea(new(0, 0, 1920, 1040), 144);
        Require(standard.Bounds.Width == 504 && standard.Bounds.Height == 156 && standard.Margin == 0,
            "150 percent monitor retains physical dimensions while flush to the work-area edges");
        Console.WriteLine("PASS achievement placement: 15 work-area/DPI cases, whole-card fitting and flush right/taskbar edges");
    }
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
