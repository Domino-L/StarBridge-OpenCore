using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// Block 3 of the visor overlay on the real view model: per-member server changes are reported,
/// one person's changes merge, and many people changing at once collapse into a few lines. The
/// standard appearance keeps one line per change.
/// </summary>
internal static class OverlayVisorEventTests
{
    private const string MyShard = "pub_use1_fixture_001";
    private static int _failures;

    private static void Check(bool value, string name, object? evidence = null)
    {
        if (!value) _failures++;
        Console.WriteLine(JsonSerializer.Serialize(new { Kind = "CHECK", Name = name, Status = value ? "PASS" : "FAIL", Evidence = evidence }));
    }

    private static PlayerRow Player(int i, string place, string ship, string shard) =>
        new($"P{i:00}", "Online", ship, "Ship: " + ship, place, Callsign: $"P{i:00}", RawLocation: place, RawShip: ship,
            ServerShard: shard, LiveStatus: "InGame", AccountId: $"P{i:00}",
            SharedOnlineStatus: "Online", SharedLiveStatus: "InGame", SharedShip: ship, SharedLocation: place);

    private static OverlayViewModel Model(OverlaySkin skin, IEnumerable<PlayerRow> rows, out OverlayDisplaySettings settings)
    {
        settings = OverlayDisplaySettings.Default with
        {
            Skin = skin, AnimationFrameRate = OverlayAnimationFrameRate.Off, ShowEventNotifications = true,
            EventNotificationTypes = OverlayEventNotificationTypes.All, EventNotificationMaxVisibleCount = 3,
        };
        var model = new OverlayViewModel(new(rows), settings, OverlayRosterSelectionSettings.Default, "zh", true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, MyShard);
        model.EventNotifications.Clear();
        return model;
    }

    private static void Refresh(OverlayViewModel model, OverlayDisplaySettings settings, IEnumerable<PlayerRow> rows) =>
        model.Refresh(new(rows), settings, OverlayRosterSelectionSettings.Default, "zh", true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, MyShard);

    private static IReadOnlyList<string> Lines(OverlayViewModel model) =>
        model.EventNotifications.Select(row => $"{row.Title}｜{row.Detail}").ToArray();

    private static int LineCount(OverlayViewModel model) => model.EventNotifications.Count + model.PendingEventNotificationCount;

    internal static void Run()
    {
        _failures = 0;
        ServerChange();
        OnePersonMerges();
        ManyPeopleCollapse();
        if (_failures != 0) throw new InvalidOperationException($"Visor event failures: {_failures}");
        Console.WriteLine("PASS visor events: server change, per-person merge, flood control");
    }

    private static void ServerChange()
    {
        foreach (var skin in new[] { OverlaySkin.Visor, OverlaySkin.Default })
        {
            var before = new[] { Player(1, "Orison", "Cutlass Black", "pub_euw1_fixture_007") };
            var model = Model(skin, before, out var settings);
            try
            {
                Refresh(model, settings, before);
                model.EventNotifications.Clear();
                Refresh(model, settings, [Player(1, "Orison", "Cutlass Black", "pub_euw1_fixture_009")]);
                var lines = Lines(model);
                Check(lines.Any(line => line.StartsWith("换服") && line.Contains("P01")), $"{skin}: a member moving between two shards that are not yours is reported", lines);
            }
            finally { model.ClearAuthorizedContent(); }
        }
    }

    private static void OnePersonMerges()
    {
        var rows = new[] { Player(1, "Orison", "Cutlass Black", "pub_euw1_fixture_007") };
        var model = Model(OverlaySkin.Visor, rows, out var settings);
        try
        {
            Refresh(model, settings, rows);
            model.EventNotifications.Clear();
            Refresh(model, settings, [Player(1, "Orison", "ANVL_Lightning_F8C", "pub_euw1_fixture_007")]);
            Refresh(model, settings, [Player(1, "Lorville", "ANVL_Lightning_F8C", "pub_euw1_fixture_007")]);
            var lines = Lines(model);
            Check(LineCount(model) == 1 && lines.Single().Contains("2 条") && lines.Single().Contains("F8C") && !lines.Single().Contains("ANVL_"), "visor: one person's ship and place changes merge into one line, with the ship's display name", lines);
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void ManyPeopleCollapse()
    {
        foreach (var skin in new[] { OverlaySkin.Visor, OverlaySkin.Default })
        {
            var before = Enumerable.Range(1, 27).Select(i => Player(i, "Orison", "Cutlass Black", i % 4 == 0 ? MyShard : "pub_euw1_fixture_007")).ToArray();
            var model = Model(skin, before, out var settings);
            try
            {
                Refresh(model, settings, before);
                model.EventNotifications.Clear();
                Refresh(model, settings, Enumerable.Range(1, 27).Select(i => Player(i, "Lorville", "Cutlass Black", i % 4 == 0 ? MyShard : "pub_euw1_fixture_007")));
                var count = LineCount(model);
                if (skin == OverlaySkin.Visor)
                    Check(count <= 11, "visor: 27 people moving at once make at most 11 lines (8 own lines, one for your server, one for everyone else)", new { count, Lines = Lines(model) });
                else
                    Check(count >= 27, "standard appearance keeps one line per change", count);
            }
            finally { model.ClearAuthorizedContent(); }
        }
    }
}
