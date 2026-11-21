using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

/// <summary>Teammate change flood control for the visor overlay (merge 20 s, more than 8 people, 30 s shared lines).</summary>
internal static class OverlayMemberChangeFloodTests
{
    private static readonly DateTimeOffset T0 = new(2026, 11, 5, 20, 0, 0, TimeSpan.Zero);

    public static void RunAll()
    {
        OnePersonMergesWithinTwentySeconds();
        ManyPeopleCollapse();
        SharedLinesRestartAfterThirtySeconds();
        ResetForgetsEverything();
    }

    private static OverlayMemberChangeLine Add(OverlayMemberChangeFlood flood, double seconds, string who, OverlayMemberChangeKind kind,
        bool pinned = false, bool same = false) =>
        flood.Add(T0.AddSeconds(seconds), who, who, pinned, same, kind, $"{OverlayMemberChangeFlood.KindTitle(kind, true)} X", $"{who} {OverlayMemberChangeFlood.KindTitle(kind, true)} X", zh: true);

    private static void OnePersonMergesWithinTwentySeconds()
    {
        var flood = new OverlayMemberChangeFlood();
        var first = Add(flood, 0, "Vega", OverlayMemberChangeKind.Place);
        True(!first.Update && first.Title == "位置变化", "first change is its own line");
        var second = Add(flood, 5, "Vega", OverlayMemberChangeKind.Ship);
        True(second.Update && second.Key == first.Key && second.Title.Contains("2 条"), $"second change within 20 s merges ({second.Title})");
        var third = Add(flood, 19, "Vega", OverlayMemberChangeKind.Server);
        True(third.Update && third.Detail.Split(" · ").Length == 3, $"third merges and lists three parts ({third.Detail})");
        var later = Add(flood, 25, "Vega", OverlayMemberChangeKind.Place);
        True(!later.Update, "a change 25 s after the line started starts a new line");
        var other = Add(flood, 26, "Lyra", OverlayMemberChangeKind.Place);
        True(!other.Update && other.Key != later.Key, "another person has a separate line");
    }

    private static void ManyPeopleCollapse()
    {
        var flood = new OverlayMemberChangeFlood();
        var keys = new HashSet<string>();
        var lines = 0;
        for (var i = 0; i < 27; i++)
        {
            var line = Add(flood, i * 0.3, $"P{i}", (OverlayMemberChangeKind)(i % 3), pinned: i == 20, same: i % 4 == 0);
            if (!line.Update) lines++;
            keys.Add(line.Key);
        }
        // 8 people get their own lines before the flood starts; then one same-server line, one
        // count line and the pinned person's own line.
        True(lines == 11, $"27 changes from 27 people make 11 lines, not 27 (got {lines})");
        True(keys.Contains(OverlayMemberChangeFlood.SameServerKey) && keys.Contains(OverlayMemberChangeFlood.OthersKey), "shared lines exist");
        True(keys.Contains(OverlayMemberChangeFlood.PersonKey("P20")), "a pinned person keeps a line of their own during a flood");
        var others = Add(flood, 9, "P30", OverlayMemberChangeKind.Ship);
        True(others.Update && others.Key == OthersKey && others.Detail.StartsWith("另有 ") && others.Detail.Contains("人换船"), $"count line counts by kind ({others.Detail})");
        var same = Add(flood, 9.5, "P31", OverlayMemberChangeKind.Place, same: true);
        True(same.Update && same.Detail.Contains("P31") && same.Detail.Contains("等 "), $"same-server line names the latest changes ({same.Detail})");
    }

    private const string OthersKey = OverlayMemberChangeFlood.OthersKey;

    private static void SharedLinesRestartAfterThirtySeconds()
    {
        var flood = new OverlayMemberChangeFlood();
        for (var i = 0; i < 12; i++) Add(flood, i, $"P{i}", OverlayMemberChangeKind.Place);
        var during = Add(flood, 12, "P12", OverlayMemberChangeKind.Place);
        True(during.Update && during.Key == OthersKey, "count line is rewritten while collecting");
        var after = Add(flood, 45, "P13", OverlayMemberChangeKind.Place);
        True(!after.Update || after.Key != OthersKey, "after 30 s the shared line does not keep growing");
    }

    private static void ResetForgetsEverything()
    {
        var flood = new OverlayMemberChangeFlood();
        Add(flood, 0, "Vega", OverlayMemberChangeKind.Place);
        flood.Reset();
        True(!Add(flood, 1, "Vega", OverlayMemberChangeKind.Ship).Update, "after a reset nothing merges into old lines");
    }

    private static void True(bool value, string name)
    {
        if (!value) throw new InvalidOperationException(name);
    }
}
