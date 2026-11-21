using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

/// <summary>
/// Visor settings and positions: untouched layouts take the visor defaults, moved modules sit where
/// they were saved, and the saved layout text never changes.
/// </summary>
internal static class OverlayVisorPlacementTests
{
    private static readonly float[] Widths = [1920, 2520, 3840]; // 16:9, 21:9, 32:9 in 1080 units

    public static void RunAll()
    {
        VisorSettings();
        FreePositions();
    }

    /// <summary>Visor settings sit at CSV 80..82: they round-trip, and files written before them read the defaults.</summary>
    internal static void VisorSettings()
    {
        var old = OverlayDisplaySettings.Parse(OverlayDisplaySettings.Default.Serialize().Split(',').Take(80) is var head ? string.Join(",", head) : "");
        True(old.VisorSize == OverlayVisorSize.Medium && !old.VisorHolidayGold, "an 80-field file reads the visor defaults");
        var first80 = string.Join(",", OverlayDisplaySettings.Default.Serialize().Split(',').Take(80));
        foreach (var size in Enum.GetValues<OverlayVisorSize>())
        foreach (var gold in new[] { false, true })
        {
            var value = OverlayDisplaySettings.Default with { VisorSize = size, VisorHolidayGold = gold };
            var csv = value.Serialize();
            var back = OverlayDisplaySettings.Parse(csv);
            True(back.VisorSize == size && back.VisorHolidayGold == gold, $"visor settings round-trip {size}/{gold}");
            // 97 columns since the 11-12 events place across (CSV 96)
            True(csv.Split(',').Length == 97 && csv.StartsWith(first80 + ",Visor,", StringComparison.Ordinal), "the first 80 fields are unchanged and column 80 is the reserved \"Visor\"");
        }
        // 11-06 "角标自由": the DM badge at CSV 83..84; files without them, or with bad values, keep the default spot.
        var badge = OverlayDisplaySettings.Default with { VisorBadgeX = 0.25, VisorBadgeY = 0.4 };
        var badgeBack = OverlayDisplaySettings.Parse(badge.Serialize());
        True(badgeBack.VisorBadgeX == 0.25 && badgeBack.VisorBadgeY == 0.4, "the badge position round-trips");
        True(old.VisorBadgeX == -1 && old.VisorBadgeY == -1, "a file from before the badge reads the default spot");
        var badBadge = OverlayDisplaySettings.Parse(string.Join(",", badge.Serialize().Split(',').Take(83)) + ",7,NaN");
        True(badBadge.VisorBadgeX == -1 && badBadge.VisorBadgeY == -1, "out-of-range badge values read the default spot");
        // 11-07 立体程度: the fold angle at CSV 85, whole degrees 0-40, default 15.
        True(old.VisorTilt == 15 && OverlayDisplaySettings.Default.VisorTilt == 15, "a file from before the tilt reads 15 degrees");
        True(OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with { VisorTilt = 32 }).Serialize()).VisorTilt == 32, "the tilt round-trips");
        var head85 = string.Join(",", OverlayDisplaySettings.Default.Serialize().Split(',').Take(85));
        True(OverlayDisplaySettings.Parse(head85 + ",90").VisorTilt == 60 && OverlayDisplaySettings.Parse(head85 + ",-5").VisorTilt == 0 &&
            OverlayDisplaySettings.Parse(head85 + ",NaN").VisorTilt == 15 && OverlayDisplaySettings.Parse(head85 + ",12.6").VisorTilt == 13,
            "a tilt out of range is clamped, rounded to whole degrees, and a bad value reads 15");
        // 11-07 聊天底框: CSV 86, on unless saved off.
        True(old.VisorChatPlate && OverlayDisplaySettings.Default.VisorChatPlate, "a file from before the chat plate keeps the plate");
        True(!OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with { VisorChatPlate = false }).Serialize()).VisorChatPlate, "the chat plate turned off round-trips");
        // 11-07 members size: CSV 87..90, adaptive with 364 x 394 by default; values clamped to their ranges.
        True(old.VisorMembersAutoWidth && old.VisorMembersAutoHeight && old.VisorMembersWidth == 364 && old.VisorMembersHeight == 394,
            "a file from before the members size reads adaptive, 364 x 394");
        var sized = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with
        {
            VisorMembersAutoWidth = false, VisorMembersAutoHeight = false, VisorMembersWidth = 300, VisorMembersHeight = 540,
        }).Serialize());
        True(sized is { VisorMembersAutoWidth: false, VisorMembersAutoHeight: false, VisorMembersWidth: 300, VisorMembersHeight: 540 }, "the members size round-trips");
        var head89 = string.Join(",", OverlayDisplaySettings.Default.Serialize().Split(',').Take(89));
        True(OverlayDisplaySettings.NormalizeVisorMembersHeight(900) == 874 &&
            OverlayDisplaySettings.NormalizeVisorMembersHeight(554) == 554,
            "twenty-row height cap preserves the former maximum");
        True(OverlayDisplaySettings.Parse(head89 + ",9000,10").VisorMembersWidth == 480 && OverlayDisplaySettings.Parse(head89 + ",9000,10").VisorMembersHeight == 191 &&
            OverlayDisplaySettings.Parse(head89 + ",300,9000").VisorMembersHeight == 874 &&
            OverlayDisplaySettings.Parse(head89 + ",NaN,x").VisorMembersWidth == 364, "a members size out of range is clamped; a bad value reads the default");
        // Review R8: an events drag that lands near the shipped height saves 0.319 / 0.361 (just outside the "never
        // moved" band); saved and parsed again, they still place the events where they were dropped.
        foreach (var y in new[] { 0.319, 0.361 })
        {
            var back = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with { EventNotificationY = y }).Serialize());
            var spots = OverlayVisorPlacement.Spots([], OverlayEventNotificationSide.Right, back.EventNotificationY, 1920);
            True(Math.Abs(back.EventNotificationY - y) < 1e-9 && spots[OverlayVisorLayout.Events].Free,
                $"an events height of {y} survives saving and still counts as moved");
        }
        // 11-07 events and chat width: CSV 91..94, adaptive with 364 by default; a round trip; out of range clamped.
        True(old is { VisorEventsAutoWidth: true, VisorChatAutoWidth: true, VisorEventsWidth: 364, VisorChatWidth: 364 },
            "a file from before the events and chat width reads adaptive, 364");
        var widths = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with
        {
            VisorEventsAutoWidth = false, VisorChatAutoWidth = false, VisorEventsWidth = 300, VisorChatWidth = 9000,
        }).Serialize());
        True(widths is { VisorEventsAutoWidth: false, VisorChatAutoWidth: false, VisorEventsWidth: 300, VisorChatWidth: 480 },
            "the events and chat width round-trip, clamped to 220-480");
        // 11-11 viewing distance (视距): CSV 95, 600-3000 in steps of 50, 1000 for a file from before it.
        True(old.VisorViewingDistance == 1000, "a file from before the viewing distance reads 1000");
        var head95 = string.Join(',', (OverlayDisplaySettings.Default).Serialize().Split(',').Take(95));
        True(OverlayDisplaySettings.Parse(head95).VisorViewingDistance == 1000, "a file of 95 columns reads 1000");
        foreach (var (saved, read) in new[] { (1650.0, 1650.0), (9000, 3000), (100, 600), (1024, 1000), (1030, 1050), (double.NaN, 1000) })
        {
            var back = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with { VisorViewingDistance = saved }).Serialize());
            True(back.VisorViewingDistance == read, $"a viewing distance of {saved} reads back as {read}");
        }
        True(OverlayDisplaySettings.Parse(head95 + ",far").VisorViewingDistance == 1000, "a bad viewing distance reads 1000");
        // 11-12 events anywhere ("应该允许事件随意调整位置了"): CSV 96, a screen fraction of their side's edge, -1 (at the
        // edge) for a file from before it or a bad value.
        True(old.VisorEventsX == -1 && OverlayDisplaySettings.Default.VisorEventsX == -1, "a file from before the events place across keeps them at the edge");
        var head96 = string.Join(',', OverlayDisplaySettings.Default.Serialize().Split(',').Take(96));
        True(OverlayDisplaySettings.Parse(head96).VisorEventsX == -1, "a file of 96 columns keeps the events at the edge");
        foreach (var (saved, read) in new[] { (0.42, 0.42), (0.0, 0.0), (1.0, 1.0), (1.4, -1.0), (-0.2, -1.0), (double.NaN, -1.0) })
        {
            var back = OverlayDisplaySettings.Parse((OverlayDisplaySettings.Default with { VisorEventsX = saved }).Serialize());
            True(back.VisorEventsX == read, $"an events place across of {saved} reads back as {read}");
        }
        True(OverlayDisplaySettings.Parse(head96 + ",mid").VisorEventsX == -1, "a bad events place across reads -1");
        // 11-06: the style column was dropped ("只保留默认的吧"). Files that saved another style still read
        // whole: column 80 is ignored and 81..82 stay in place. Nothing rewrites the file for this column; the next save writes "Visor" there.
        foreach (var style in new[] { "Visor", "ColdLine", "DeepVisor", "Nope" })
        {
            var saved = first80 + $",{style},Large,1";
            var read = OverlayDisplaySettings.Parse(saved);
            True(read.VisorSize == OverlayVisorSize.Large && read.VisorHolidayGold, $"a file saved with style {style} keeps its size and gold");
            True(read with { } == OverlayDisplaySettings.Parse(first80 + ",Visor,Large,1"), $"style {style} reads the same as the visor projection");
        }
        var garbage = first80 + ",Nope,Huge,7";
        var parsed = OverlayDisplaySettings.Parse(garbage);
        True(parsed.VisorSize == OverlayVisorSize.Medium && !parsed.VisorHolidayGold, "unknown visor values fall back to the defaults");
    }

    /// <summary>
    /// 11-06 free positions ("可以像现在一样自由调整吗"): untouched layouts take the visor defaults, a
    /// moved module sits at its saved corner, groups stay on screen and apart, the saved text never changes.
    /// </summary>
    internal static void FreePositions()
    {
        foreach (var width in Widths)
        {
            foreach (var (payload, name) in new[]
            {
                (InformationOverlayDefaults.DefaultLayoutPayload, "shipped default layout"),
                ("Notice,0.34,0,0.32,0.055;Squads,0.01,0.36,0.13,0.24;Members,0.84,0.58,0.15,0.18;Chat,0.35,0.78,0.30,0.18", "editor template A"),
                ("Notice,0.285,0,0.43,0.075;Squads,0.01,0.30,0.18,0.42;Members,0.78,0.54,0.21,0.26;Chat,0.35,0.75,0.30,0.21", "editor template B"),
                ("", "no saved layout"),
                ("Members,0.004,0.527,0.1327,0.1557,Right,Middle,0,1,0.5", "nudged within the unmoved tolerance"),
            })
            {
                var spots = Spots(payload, width);
                foreach (var (group, slot) in OverlayVisorLayout.DefaultLayout)
                    Equal(slot, spots[group].Slot ?? "free", $"{width}: {name} gives {group} the visor default");
                True(spots.Count == 3, $"{width}: {name} places exactly the three groups");
            }

            var upperLeft = Spots("Members,0.01,0.1,0.13,0.16,Left,Top", width)[OverlayVisorLayout.Team];
            True(upperLeft is { Free: true, Right: false, Bottom: false } && Near(upperLeft.X, 0.01f * width) && Near(upperLeft.Y, 108),
                $"{width}: members moved to the upper left sit at their saved top-left corner ({upperLeft})");
            var lowerRight = Spots("Members,0.6,0.55,0.13,0.16,Right,Bottom", width)[OverlayVisorLayout.Team];
            True(lowerRight is { Free: true, Right: true, Bottom: true } && Near(lowerRight.X, 0.73f * width) && Near(lowerRight.Y, 0.71f * 1080),
                $"{width}: members anchored right and bottom keep that corner ({lowerRight})");
            var centred = Spots("Chat,0.6,0.7,0.2,0.12,Center,Middle", width)[OverlayVisorLayout.Chat];
            True(centred is { Free: true, Right: true, Bottom: true }, $"{width}: a centred module takes the corner of the screen half it is in ({centred})");
            var notice = Spots("Notice,0.1,0.3,0.32,0.055,Left,Top", width);
            True(notice.Count == 3 && notice.Values.All(spot => !spot.Free), $"{width}: a moved notice leaves the rally at the top centre and the rest at their defaults");

            var left = OverlayVisorPlacement.Spots([], OverlayEventNotificationSide.Left, OverlayVisorPlacement.DefaultEventY, width)[OverlayVisorLayout.Events];
            True(left is { Free: true, Right: false } && Near(left.X, OverlayVisorLayout.Edge), $"{width}: events on the left side sit on the left edge");
            var lower = OverlayVisorPlacement.Spots([], OverlayEventNotificationSide.Right, 0.6, width)[OverlayVisorLayout.Events];
            True(lower is { Free: true, Right: true } && Near(lower.Y, 0.6f * (1080 - 90)), $"{width}: events moved down keep their height");
            // 11-12: anywhere across, from the side's edge; at the shipped height too, a place across counts as moved
            var across = OverlayVisorPlacement.Spots([], OverlayEventNotificationSide.Right, OverlayVisorPlacement.DefaultEventY, width, 0.7)[OverlayVisorLayout.Events];
            True(across is { Free: true, Right: true } && Near(across.X, 0.7f * width), $"{width}: events placed across sit there, read from their right edge ({across})");
            var leftAcross = OverlayVisorPlacement.Spots([], OverlayEventNotificationSide.Left, 0.5, width, 0.3)[OverlayVisorLayout.Events];
            True(leftAcross is { Free: true, Right: false } && Near(leftAcross.X, 0.3f * width), $"{width}: events on the left read from their left edge ({leftAcross})");
            var unset = OverlayVisorPlacement.Spots([], OverlayEventNotificationSide.Right, OverlayVisorPlacement.DefaultEventY, width, -1)[OverlayVisorLayout.Events];
            True(!unset.Free, $"{width}: unset across at the shipped height and side is still the default slot");
        }

        // 11-06 "召集应该可以上下换位 但是固定两个预设位置": read from where the notice module is docked.
        True(!OverlayVisorPlacement.RallyAtBottom(InformationOverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload), 1920), "the rally starts at the top centre");
        True(OverlayVisorPlacement.RallyAtBottom(InformationOverlayLayoutItem.ParseMany("Notice,0.1,0.945,0.32,0.055,Left,Bottom"), 1920), "a notice docked to the bottom puts the rally at the bottom centre");
        True(!OverlayVisorPlacement.RallyAtBottom([], 1920), "no notice module: top centre");

        var defaultBadge = OverlayVisorPlacement.Badge(-1, -1, 1920);
        True(!defaultBadge.Free && defaultBadge.RightAligned, "an unset badge keeps its default spot, reading from the right");
        var leftBadge = OverlayVisorPlacement.Badge(0.1, 0.5, 1920);
        True(leftBadge is { Free: true, Right: false } && Near(leftBadge.X, 192) && Near(leftBadge.Y, 540) && !leftBadge.RightAligned,
            "a badge placed on the left hangs from its left edge");
        var rightBadge = OverlayVisorPlacement.Badge(0.9, 0.2, 2520);
        True(rightBadge is { Free: true, Right: true } && Near(rightBadge.X, 2268) && rightBadge.RightAligned, "a badge on the right hangs from its right edge");

        // The saved layout is read, never rewritten.
        var items = InformationOverlayLayoutItem.ParseMany("Members,0.85,0.12,0.13,0.16,Right,Top;Chat,0.35,0.84,0.3,0.12").ToArray();
        var before = InformationOverlayLayoutItem.SerializeMany(items);
        OverlayVisorPlacement.Spots(items, OverlayEventNotificationSide.Right, OverlayVisorPlacement.DefaultEventY, 1920);
        Equal(before, InformationOverlayLayoutItem.SerializeMany(items), "reading positions leaves the saved layout unchanged");

        // Arrange: free groups where the user put them, on screen, apart.
        var sizes = new Dictionary<string, (float W, float H)> { [OverlayVisorLayout.Team] = (255, 350), [OverlayVisorLayout.Events] = (255, 160), [OverlayVisorLayout.Chat] = (255, 90) };
        var free = new Dictionary<string, OverlayVisorSpot>
        {
            [OverlayVisorLayout.Team] = new(null, 600, 300),
            [OverlayVisorLayout.Events] = OverlayVisorSpot.At("R-top"),
            [OverlayVisorLayout.Chat] = new(null, 600, 400),
        };
        var pos = OverlayVisorLayout.Arrange(free, sizes, 1920);
        True(Near(pos[OverlayVisorLayout.Team].X, 600) && Near(pos[OverlayVisorLayout.Team].Y, 300), "a free group sits exactly where it was put");
        True(Near(pos[OverlayVisorLayout.Chat].Y, 300 - OverlayVisorLayout.Gap - 90), "a free group dropped onto another moves just clear of it, the shorter way (here up)");
        var offscreen = OverlayVisorLayout.Arrange(new() { [OverlayVisorLayout.Team] = new(null, 1990, -40, Right: true) }, new Dictionary<string, (float W, float H)> { [OverlayVisorLayout.Team] = (255, 350) }, 1920);
        True(Near(offscreen[OverlayVisorLayout.Team].X, 1920 - OverlayVisorLayout.ScreenMargin - 255) && Near(offscreen[OverlayVisorLayout.Team].Y, OverlayVisorLayout.ScreenMargin), "a group past the screen edge is kept on screen");
        var crowd = OverlayVisorLayout.Arrange(new() { [OverlayVisorLayout.Team] = new(null, 1800, 150, Right: true), [OverlayVisorLayout.Events] = OverlayVisorSpot.At("R-top") }, new Dictionary<string, (float W, float H)> { [OverlayVisorLayout.Team] = (255, 350), [OverlayVisorLayout.Events] = (255, 160) }, 1920);
        // m102 (11-18 user): the events give way up, never the members; at the top of their column they overlap
        True(Near(crowd[OverlayVisorLayout.Team].Y, 150) && Near(crowd[OverlayVisorLayout.Events].Y, 150) &&
            OverlayVisorLayout.EventsOverlap(crowd, new Dictionary<string, (float W, float H)> { [OverlayVisorLayout.Team] = (255, 350), [OverlayVisorLayout.Events] = (255, 160) }) is not null,
            "the members the user placed at the top stay; the events can go no higher and overlap them (the editors warn)");
        // m102 (11-18 user: "12 人", "往下延长", "事件…应该自己向上避开"): the default preset's members are 12 rows
        // high and keep their top; its events sit above them and grow up with the most events at once
        var preset = InformationOverlayDefaults.DefaultSettings;
        True(preset.VisorMembersHeight == 554 && Math.Abs(preset.EventNotificationY - 0.254) < 1e-9 &&
            OverlayDisplaySettings.Default.VisorMembersHeight == 394 && Math.Abs(OverlayDisplaySettings.Default.EventNotificationY - 0.34) < 1e-9,
            "only the default preset changes: members 554, events 0.254");
        foreach (var count in new[] { 3, 4, 5 })
        {
            var spots = OverlayVisorPlacement.Spots(InformationOverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload),
                preset.EventNotificationSide, preset.EventNotificationY, 1920);
            var groupSizes = new Dictionary<string, (float W, float H)>
            {
                [OverlayVisorLayout.Team] = (364 * 0.53f, 554 * 0.53f),
                [OverlayVisorLayout.Events] = (364 * 0.53f, (22 + count * 70) * 0.53f),
            };
            var at = OverlayVisorLayout.Arrange(spots, groupSizes, 1920);
            var team = new OverlayVisorRect(at[OverlayVisorLayout.Team].X, at[OverlayVisorLayout.Team].Y, groupSizes[OverlayVisorLayout.Team].W, groupSizes[OverlayVisorLayout.Team].H);
            var events = new OverlayVisorRect(at[OverlayVisorLayout.Events].X, at[OverlayVisorLayout.Events].Y, groupSizes[OverlayVisorLayout.Events].W, groupSizes[OverlayVisorLayout.Events].H);
            True(Near(team.Y, OverlayVisorLayout.RightMidTop) && Near(team.Y, 385.6f) && team.Bottom < 790,
                $"{count} events: the members keep their top (386) and end above the key hints ({team})");
            True(Near(events.Bottom + OverlayVisorLayout.Gap, team.Y) && events.Y >= 150 && !events.Hits(team) &&
                OverlayVisorLayout.EventsOverlap(at, groupSizes) is null && Near(events.Right, team.Right),
                $"{count} events: they sit just above the members, under the corner icons, right edges aligned ({events})");
        }

        // review CX-OVERLAY-M102-R1 P2-1: the gap counts below the members too, and a ceiling never pushes the events
        // toward them
        var gapSizes = new Dictionary<string, (float W, float H)>
        {
            [OverlayVisorLayout.Team] = (193, 294.4f),
            [OverlayVisorLayout.Events] = (193, 123),
        };
        var below = OverlayVisorLayout.Arrange(new()
        {
            [OverlayVisorLayout.Team] = new(null, 1864, 300, Right: true),
            [OverlayVisorLayout.Events] = new(null, 1864, 604, Right: true),
        }, gapSizes, 1920);
        True(Near(below[OverlayVisorLayout.Team].Y, 300) && Near(below[OverlayVisorLayout.Events].Y, 300 + 294.4f + OverlayVisorLayout.Gap),
            "events a few units under the members move down to a gap below them; the members stay");
        var high = OverlayVisorLayout.Arrange(new()
        {
            [OverlayVisorLayout.Team] = new(null, 1864, 198, Right: true),
            [OverlayVisorLayout.Events] = new(null, 1864, 100, Right: true),
        }, new Dictionary<string, (float W, float H)> { [OverlayVisorLayout.Team] = (193, 294.4f), [OverlayVisorLayout.Events] = (193, 85.9f) }, 1920);
        True(Near(high[OverlayVisorLayout.Events].Y, 100) && Near(high[OverlayVisorLayout.Team].Y, 198),
            "events placed above the column top stay there; the ceiling does not push them down onto the members");
        // review P2-2 (11-18 user: "成员不挪，事件让，让不开就重叠"): an overflowing right column (large, 554 high, five
        // events never moved) keeps the members on the right; the events stay at 150 over them
        const float large = 0.53f * 1.36f;
        var overflowSizes = new Dictionary<string, (float W, float H)>
        {
            [OverlayVisorLayout.Team] = (364 * large, 554 * large),
            [OverlayVisorLayout.Events] = (364 * large, (22 + 5 * 70) * large),
        };
        var overflow = OverlayVisorLayout.Arrange(OverlayVisorPlacement.Spots(
            InformationOverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload),
            OverlayEventNotificationSide.Right, OverlayVisorPlacement.DefaultEventY, 1920), overflowSizes, 1920);
        True(overflow[OverlayVisorLayout.Team].X > 960 && Near(overflow[OverlayVisorLayout.Team].Y, OverlayVisorLayout.RightMidTop) &&
            Near(overflow[OverlayVisorLayout.Events].Y, 150) && OverlayVisorLayout.EventsOverlap(overflow, overflowSizes) is not null,
            "an overflowing right column keeps the members on the right; the events stay at 150 over them");
        // review P2-3: at the edge of "never moved" (0.36) Core and the editors agree: the default slot
        True(!OverlayVisorPlacement.Spots([], OverlayEventNotificationSide.Right, 0.36, 1920)[OverlayVisorLayout.Events].Free,
            "events at 0.36 read as never moved, as the editors read them");

        // m102 (11-18 user: "0.7.3 做甲"): the size a preset never saved starts with, from the screen's physical height
        // (the visor's text is a fixed share of it); never small; without a believable height, from pixels and scaling
        foreach (var (facts, expected, name) in new (OverlayScreenFacts, OverlayVisorSize, string)[]
        {
            (new(1080, 1.25, 194), OverlayVisorSize.Large, "15.6\" 1080p laptop"),
            (new(1600, 1.5, 215), OverlayVisorSize.Large, "16\" 2560x1600 laptop"),
            (new(1080, 1.0, 299), OverlayVisorSize.Medium, "24\" 1080p"),
            (new(1440, 1.0, 336), OverlayVisorSize.Medium, "27\" 1440p"),
            (new(1440, 1.0, 333), OverlayVisorSize.Medium, "34\" 3440x1440"),
            (new(2160, 1.0, 600), OverlayVisorSize.Medium, "a big screen is never small"),
            (new(1080, 1.25, null), OverlayVisorSize.Large, "no height: 1080 rows at 125%"),
            (new(1200, 1.25, 0), OverlayVisorSize.Large, "an unbelievable height (0): 1200 rows at 125%"),
            (new(1600, 1.5, 5000), OverlayVisorSize.Large, "an unbelievable height (5 m): 1600 rows at 150%"),
            (new(1440, 1.25, null), OverlayVisorSize.Medium, "no height: 1440 rows at 125% (a desktop)"),
            (new(2160, 1.5, null), OverlayVisorSize.Medium, "no height: 4K at 150%"),
            (new(1080, 1.0, null), OverlayVisorSize.Medium, "no height: 1080 rows at 100%"),
            (new(0, 1, null), OverlayVisorSize.Medium, "nothing known"),
            (new(1080, double.NaN, double.NaN), OverlayVisorSize.Medium, "not numbers"),
        })
            True(OverlayVisorAutoSize.Pick(facts) == expected, $"visor auto size: {name} -> {expected}");

        // build 72 acceptance: members moved to the left edge, ending at y 783, over the untouched chat's default spot.
        var leftTeam = OverlayVisorLayout.Arrange(
            new() { [OverlayVisorLayout.Team] = new(null, 0, 783, Right: false, Bottom: true), [OverlayVisorLayout.Chat] = OverlayVisorSpot.At("L-bottom") },
            new Dictionary<string, (float W, float H)> { [OverlayVisorLayout.Team] = (255, 350), [OverlayVisorLayout.Chat] = (255, 104) }, 1920);
        True(Near(leftTeam[OverlayVisorLayout.Team].Y, 433) && Near(leftTeam[OverlayVisorLayout.Chat].Y, 783 + OverlayVisorLayout.Gap),
            "the untouched chat gives way to the members the user placed, the shorter way (here down)");

        var random = new Random(73);
        for (var i = 0; i < 400; i++)
        {
            var width = Widths[i % Widths.Length];
            var spots = new Dictionary<string, OverlayVisorSpot>
            {
                [OverlayVisorLayout.Team] = new(null, (float)random.NextDouble() * width, (float)random.NextDouble() * 1080, random.Next(2) == 0, random.Next(2) == 0),
                [OverlayVisorLayout.Events] = random.Next(2) == 0 ? OverlayVisorSpot.At("R-top") : new(null, (float)random.NextDouble() * width, (float)random.NextDouble() * 1080),
                [OverlayVisorLayout.Chat] = new(null, (float)random.NextDouble() * width, (float)random.NextDouble() * 1080, random.Next(2) == 0, random.Next(2) == 0),
            };
            var placed = OverlayVisorLayout.Arrange(spots, sizes, width);
            var boxes = placed.Select(kv => (kv.Key, Box: new OverlayVisorRect(kv.Value.X, kv.Value.Y, sizes[kv.Key].W, sizes[kv.Key].H))).ToArray();
            True(boxes.All(b => b.Box.X >= 0 && b.Box.Y >= 0 && b.Box.Right <= width + 0.01f && b.Box.Bottom <= 1080.01f), $"random {i}: every group stays on screen");
            // the one overlap allowed (m102): events that gave way as far as they may (the top of their column, or
            // the bottom of the screen), onto the members
            bool Allowed((string Key, OverlayVisorRect Box) a, (string Key, OverlayVisorRect Box) b) =>
                new[] { a.Key, b.Key }.Order().SequenceEqual(new[] { OverlayVisorLayout.Events, OverlayVisorLayout.Team }.Order()) &&
                (a.Key == OverlayVisorLayout.Events ? a.Box : b.Box) is var ev &&
                (ev.Y <= OverlayVisorLayout.EventsCeiling(ev.X, ev.W, width) + 0.5f || ev.Y >= OverlayVisorLayout.EventsFloor(ev.H) - 0.5f);
            True(!boxes.Any(a => boxes.Any(b => string.CompareOrdinal(a.Key, b.Key) < 0 && a.Box.Hits(b.Box) && !Allowed(a, b))),
                $"random {i}: groups never overlap but for events at their ceiling on the members ({string.Join("; ", boxes.Select(b => $"{b.Key} {b.Box}"))})");
        }
    }

    private static Dictionary<string, OverlayVisorSpot> Spots(string payload, float width) =>
        OverlayVisorPlacement.Spots(InformationOverlayLayoutItem.ParseMany(payload), OverlayEventNotificationSide.Right, OverlayVisorPlacement.DefaultEventY, width);

    private static bool Near(float a, float b) => MathF.Abs(a - b) < 1f;

    private static void Equal(string expected, string actual, string name)
    {
        if (expected != actual) throw new InvalidOperationException($"{name}: expected {expected}, got {actual}");
    }

    private static void True(bool value, string name)
    {
        if (!value) throw new InvalidOperationException(name);
    }
}
