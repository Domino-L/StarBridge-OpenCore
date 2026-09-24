using StarBridge.Core.Hangar;

namespace StarBridge.Core.Tests;

internal static class HangarScanSessionTests
{
    public static void RunAll()
    {
        StableScanPreservesInstances();
        RejectsIncompleteAndChangedPages();
        KeepsUnknownAndEmptySeparate();
        BoundsCancellationAndCopies();
        AncillaryTitlesNeverOverrideShipEvidence();
    }

    private static HangarPledgeObservation Pledge(string key, params HangarItemObservation[] items) => new(key, null, items);
    private static void AncillaryTitlesNeverOverrideShipEvidence()
    {
        foreach (var item in new[] {
            new HangarItemObservation("ADP-mk4 'SecondWind' Core", null, "Manufacturer"),
            new HangarItemObservation("ADP-mk4 'SecondWind' Core", "New Kind", null),
            new HangarItemObservation("Unknown Ship", null, null),
            new HangarItemObservation("Core", null, null),
            new HangarItemObservation("Ship with Helmet", null, null),
            new HangarItemObservation("ADP-mk4 'SecondWind' Core Upgrade", null, null) })
        {
            ulong sequence = 0;
            var result = Twice(new(), Page(1, 1, null, Pledge("fixture", item)), ref sequence);
            Require(result.IsComplete && result.Ships.Count == 0,
                "Like WPF, titles and manufacturers must not promote a non-ship item into the inventory");
        }
        ulong seq = 0;
        var ships = Twice(new(), Page(1, 1, null, Pledge("fixture", Ship("VFG Industrial Hangar"),
            Ship("Model absent from catalog"))), ref seq);
        Require(ships.IsComplete && ships.Ships.Count == 2, "Explicit ship kind must win over an accessory-looking name");
    }
    private static HangarItemObservation Ship(string title = "Test Ship") => new(title, "Ship", "Test Manufacturer");
    private static HangarPageObservation Page(int page, int? total, int? next, params HangarPledgeObservation[] pledges) => new(page, total, next, true, pledges);
    private static HangarScanSnapshot Twice(HangarScanSession scan, HangarPageObservation page, ref ulong sequence)
    { scan.Observe(++sequence, page); return scan.Observe(++sequence, page); }
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }

    private static void StableScanPreservesInstances()
    {
        var scan = new HangarScanSession(); ulong sequence = 0;
        var first = Page(1, 2, 2, Pledge("pledge-a", Ship(), Ship()));
        scan.Observe(++sequence, first);
        Require(scan.Observe(sequence, first).Pages.Count == 0, "One capture cannot prove stability twice");
        Require(scan.Observe(++sequence, first).ExpectedPage == 2, "Stable first page must advance");
        Require(scan.Observe(++sequence, first).Pages.Count == 1, "Page replay must not duplicate ships");
        var last = Page(2, null, null, Pledge("pledge-A", Ship("Unknown Catalog Model")));
        var waiting = Twice(scan, last, ref sequence);
        Require(waiting.State == HangarScanState.VerifyingFirstPage && waiting.ExpectedPage == 1, "Require first-page recheck");
        var result = Twice(scan, first, ref sequence);
        Require(result.IsComplete && result.Ships.Count == 3 && result.Pages.Count == 2, "Preserve every ship occurrence");
        Require(result.Ships[0].PledgeKey == result.Ships[1].PledgeKey && result.Ships[0].ItemIndex != result.Ships[1].ItemIndex, "Parent pledge is not child identity");
        Require(result.Ships.All(s => s.AcquiredText is null), "Unknown acquisition date must remain absent");
    }

    private static void RejectsIncompleteAndChangedPages()
    {
        foreach (var malformed in new[] {
            Page(2, 2, null, Pledge("later", Ship())),
            Page(1, 2, 3, Pledge("gap", Ship())),
            Page(1, 1, null, Pledge("same", Ship()), Pledge("same", Ship())) })
        {
            var scan = new HangarScanSession(); ulong sequence = 0;
            Require(Twice(scan, malformed, ref sequence).State == HangarScanState.Invalid, "Reject skipped pages or duplicate keys");
        }
        foreach (var second in new[] {
            Page(2, 3, 3, Pledge("b", Ship())),
            Page(2, null, null, Pledge("a", Ship())),
            Page(2, 2, 3, Pledge("b", Ship())) })
        {
            var scan = new HangarScanSession(); ulong sequence = 0;
            Twice(scan, Page(1, 2, 2, Pledge("a", Ship())), ref sequence);
            Require(Twice(scan, second, ref sequence).State == HangarScanState.Invalid, "Reject changing totals or cross-page duplicates");
        }
        var changed = new HangarScanSession(); ulong seq = 0;
        var first = Page(1, 2, 2, Pledge("a", Ship()));
        Twice(changed, first, ref seq);
        Twice(changed, Page(2, null, null, Pledge("b", Ship())), ref seq);
        Require(Twice(changed, first with { Pledges = [Pledge("c", Ship())] }, ref seq).Issue == HangarScanIssue.PageChanged, "Bookend detects content change");
        var unknownTotal = new HangarScanSession(); seq = 0;
        Require(Twice(unknownTotal, Page(1, null, null, Pledge("a", Ship())), ref seq).Issue == HangarScanIssue.MissingPaginationProof, "Missing next is not total proof");
    }

    private static void KeepsUnknownAndEmptySeparate()
    {
        var mixed = new HangarScanSession(); ulong mixedSequence = 0;
        var allPages = Twice(mixed, Page(1, 1, null, Pledge("mixed", Ship("Model absent from local catalog"),
            new("Unidentified extra", "New Kind", null))), ref mixedSequence);
        Require(allPages.IsComplete && allPages.Pages.Count == 1 &&
            allPages.Ships.Count == 1 && allPages.UnclassifiedCount == 1,
            "Non-ship items must not block a complete ship inventory");
        foreach (var page in new[] {
            Page(1, 1, null, Pledge("a", new HangarItemObservation("Unclassified content", null, null))),
            Page(1, 1, null, Pledge("a")),
            Page(1, 1, null, Pledge("a", new HangarItemObservation("New type", "New Kind", null))) })
        {
            var scan = new HangarScanSession(); ulong seq = 0;
            var result = Twice(scan, page, ref seq);
            Require(result.IsComplete && result.Ships.Count == 0,
                "Non-ship contents and empty packages are ignored after page verification");
        }
        var empty = new HangarScanSession(); ulong sequence = 0;
        Require(Twice(empty, Page(1, 1, null), ref sequence).Issue == HangarScanIssue.UnconfirmedEmpty, "Empty parse is not empty hangar proof");
        var nonShip = new HangarScanSession(); sequence = 0;
        var known = Twice(nonShip, Page(1, 1, null, Pledge("a", new("Paint", "Skin", null), new("Armor", "FPS Equipment", null), new("Cover", "Insurance", null))), ref sequence);
        Require(known.IsComplete && known.Ships.Count == 0, "Complete verified pages can contain no ships");
    }

    private static void BoundsCancellationAndCopies()
    {
        var clock = new Clock(); var timeout = new HangarScanSession(clock);
        clock.Ticks = TimeSpan.FromMinutes(10).Ticks;
        Require(timeout.Snapshot.State == HangarScanState.TimedOut, "Finite scan deadline");
        var cancelled = new HangarScanSession(); cancelled.Cancel(); ulong sequence = 0;
        Require(Twice(cancelled, Page(1, 1, null, Pledge("a", Ship())), ref sequence).State == HangarScanState.Cancelled, "Cancel cannot be revived by late captures");
        foreach (var bad in new[] {
            Page(1, 101, 2, Pledge("a", Ship())),
            Page(1, 1, null, Pledge("a", Ship(new string('x', 257)))),
            Page(1, 1, null, Pledge("a", Ship())) with { Unfiltered = false } })
        {
            sequence = 0;
            Require(Twice(new HangarScanSession(), bad, ref sequence).State == HangarScanState.Invalid, "Reject bounds or filters");
        }
        var items = new List<HangarItemObservation> { Ship() };
        var original = Page(1, 1, null, new HangarPledgeObservation("a", null, items));
        var copied = new HangarScanSession(); sequence = 0;
        var result = Twice(copied, original, ref sequence);
        items.Clear();
        Require(result.Ships.Count == 1 && result.Pages[0].Pledges[0].Items.Count == 1 && copied.Snapshot.Ships.Count == 1, "Caller mutation must not edit an accepted page");
    }

    private sealed class Clock : TimeProvider
    {
        public long Ticks { get; set; }
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => Ticks;
    }
}
