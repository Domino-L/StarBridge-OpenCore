using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.Core.Presence;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;

namespace StarBridge.Desktop.Tests;

internal static class SharedShipEventCardsTests
{
    internal static void RunAll()
    {
        var failures = new List<string>();
        foreach (var test in new Action[] { KnownShipsReachActualQueue, LateDataAndRevocationRefreshCards, LocalSeatIdentifierIsLocalized, ObservedRavenExIsIndependent })
            try { test(); Console.WriteLine("PASS ship event cards " + test.Method.Name); }
            catch (Exception error) { failures.Add(test.Method.Name + ": " + error.Message); }
        if (failures.Count > 0) throw new Exception(string.Join(Environment.NewLine, failures));
    }
    private static readonly OverlayDisplaySettings Settings = OverlayDisplaySettings.Default with
        { AnimationFrameRate = OverlayAnimationFrameRate.Off, EventNotificationMaxVisibleCount = 6 };
    private const string Key = "fixture-stable-publisher";
    private static OverlayViewModel Model(IReadOnlyList<PlayerRow> rows, string language) =>
        new(new(rows), Settings, OverlayRosterSelectionSettings.Default, language, true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
    private static IReadOnlyList<PlayerRow> Rows(string ship, bool room, string language)
    {
        var roomData = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
            [new("Same name", "Peer", false, "InGame", "", ship, "US") { PreferenceKey = Key }], []);
        var community = new InformationOverlayCommunityContent("fixture", "Community",
            [new("Peer", "Same name", "Member", "InGame", ship, "", "US", false) { PreferenceKey = Key }]);
        return NativeInformationOverlayRuntime.ProjectSource(room ? roomData : null, room ? null : community,
            OverlayScenePreference.Auto, language).Scene.Players;
    }
    private static bool Deliver(OverlayViewModel model, SharedActivityNotice notice, IReadOnlyList<PlayerRow> rows,
        string language, OverlayLocalEventDeliveryGate? gate = null) => NativeInformationOverlayRuntime.TryQueueSharedActivity(
            notice, Settings, true, language, gate ?? new(), false, rows,
            (category, title, detail, positive, current, update) => model.QueueGameEventNotification(
                category, title, detail, false, positive, current, update));
    private static SharedActivityNotice Notice(string type) => new("Same name",
        new(Guid.NewGuid().ToString("N"), type, DateTimeOffset.UtcNow), () => true) { PublisherKey = Key };
    private static void KnownShipsReachActualQueue()
    {
        using var pack = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var json = JsonDocument.Parse(pack);
        var names = json.RootElement.GetProperty("entries").EnumerateArray()
            .SelectMany(row => new[] { row.GetProperty("runtimeId").GetString()!, row.GetProperty("englishName").GetString()! }
                .Concat(row.GetProperty("aliases").EnumerateArray().Select(alias => alias.GetString()!)))
            .Where(raw => GameShipNames.Find(raw) is not null).ToArray();
        VerifyKnownInputs(names);
    }
    internal static void FullDisplayCatalog(string path)
    {
        var lines = System.IO.File.ReadAllLines(path);
        var header = lines[0].TrimStart('\uFEFF').Split('\t');
        var column = Array.IndexOf(header, "英文飞船名");
        Check(column >= 0, "existing catalog has its English display-name column");
        var names = lines.Skip(1).Select(line => line.Split('\t')).Where(row => row.Length > column)
            .Select(row => row[column].Trim()).Where(value => value.Length > 0).ToArray();
        Check(names.All(raw => GameShipNames.Find(raw) is not null), "every full display-catalog model must be translated before event rendering");
        VerifyKnownInputs(names);
    }
    private static void VerifyKnownInputs(string[] names)
    {
        foreach (var raw in names)
        foreach (var room in new[] { false, true })
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        foreach (var type in new[] { "PlayerEnteredShip", "PlayerControllingShip", "PlayerStoppedDrivingShip", "PlayerExitedShip" })
        {
            var rows = Rows(raw, room, language);
            var model = Model(rows, language); model.EventNotifications.Clear();
            try
            {
                Check(Deliver(model, Notice(type), rows, language), "actual shared queue accepts a current ship event");
                var name = GameShipNames.Find(raw)!;
                var expected = language == "en" ? name.EnglishName : language == "zh-Hant" ? name.TraditionalChineseName ?? name.ChineseName : name.ChineseName;
                var detail = model.EventNotifications.Single().Detail;
                Check(detail.Contains(expected) && detail.Contains(language == "en" ? "Current ship:" : language == "zh-Hant" ? "目前艦船：" : "当前舰船："),
                    $"{type} must supplement the independently authorized current ship, room={room}, language={language}, raw={raw}, actual={detail}");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        Console.WriteLine($"PASS {names.Length} ship inputs x two scenes x three languages x four shared ship event types");
    }
    private static void LateDataAndRevocationRefreshCards()
    {
        var rows = Rows("", true, "zh");
        var model = Model(rows, "zh"); model.EventNotifications.Clear();
        try
        {
            var notice = Notice("PlayerStoppedDrivingShip");
            Deliver(model, notice, rows, "zh");
            var card = model.EventNotifications.Single();
            Refresh(Rows("ANVL_Lightning_F8C", true, "zh"));
            Check(card.Detail.Contains("当前舰船：F8C 闪电"), "late authorized data updates an existing card");
            Refresh(Rows("AEGS_Avenger_Titan", true, "zh"));
            Check(!card.Detail.Contains("F8C") && card.Detail.Contains("当前舰船："),
                "later ship changes are explicitly current information, never a fabricated historical seat/ship");
            Refresh(Rows("", true, "zh"));
            Check(!card.Detail.Contains("当前舰船："), "withdrawn ship sharing removes details");
            var known = Rows("ANVL_Lightning_F8C", true, "zh");
            foreach (var unauthorized in new IReadOnlyList<PlayerRow>[] { [], [known[0], known[0]],
                [known[0] with { AccountId = "different", Callsign = "Same name" }],
                [known[0] with { SharedLiveStatus = "AppOnline" }], [known[0] with { SharedHasServerSession = false }] })
            {
                Refresh(unauthorized);
                Check(!model.EventNotifications.Contains(card) || !card.Detail.Contains("F8C"),
                    "ambiguous/missing identity and inactive session do not supplement ship: count=" + unauthorized.Count +
                    ", presence=" + unauthorized.FirstOrDefault()?.SharedPresence + ", key=" + unauthorized.FirstOrDefault()?.AccountId + ", detail=" + card.Detail);
            }
            void Refresh(IReadOnlyList<PlayerRow> next) => model.Refresh(new(next), Settings,
                OverlayRosterSelectionSettings.Default, "zh", true, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
        }
        finally { model.ClearAuthorizedContent(); }
    }
    private static void LocalSeatIdentifierIsLocalized()
    {
        using var pack = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var json = JsonDocument.Parse(pack);
        var rows = json.RootElement.GetProperty("entries").EnumerateArray().ToArray();
        foreach (var row in rows)
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        {
            var raw = row.GetProperty("runtimeId").GetString()!;
            var name = GameShipNames.Find(raw)!;
            var expected = language == "en" ? name.EnglishName : language == "zh-Hant" ? name.TraditionalChineseName ?? name.ChineseName : name.ChineseName;
            var model = Model([], language); model.EventNotifications.Clear();
            try
            {
                var notice = new LocalGameOverlayNotice(Guid.NewGuid().ToString("N"), "PlayerStoppedDrivingShip",
                    LifeEventContext.Unknown, () => true, raw + "_987654321");
                NativeInformationOverlayRuntime.TryQueueLocalGameEvent(notice, Settings, true, language, new(),
                    (category, title, detail, important, positive, current, local) =>
                        model.QueueGameEventNotification(category, title, detail, important, positive, current, isDeviceLocal: local));
                Check(model.EventNotifications.Single().Detail.EndsWith(" · " + expected), "every known runtime model with entity suffix is translated at the local queue boundary: " + raw);
                Check(GameShipNames.Find(raw + "_Variant_987654321") is null, "display suffix parsing never guesses a different variant");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        Console.WriteLine($"PASS {rows.Length} local pilot-seat entity labels in three languages; variants remain exact");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static void ObservedRavenExIsIndependent()
    {
        var exact = GameShipNames.Find("AEGS_Sabre_Raven_EX");
        Check(exact?.EnglishName == "Sabre Raven EX" && exact.ChineseName == "渡鸦EX" && exact.RuntimeId == "AEGS_Sabre_Raven_EX",
            "the newly supplied exact runtime identifier resolves the independent Raven EX model");
        Check(GameShipNames.Find("AEGS_Sabre_Raven")?.RuntimeId != exact!.RuntimeId, "Raven EX never aliases the base Raven");
    }
}
