using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayRosterPreferencesTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-roster-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var owner = new BridgeAccountContext("test", "scm", "synthetic-owner");
            var key = OverlayMemberIdentity.FromAccountId("synthetic-member")!;
            var member = new InformationOverlayRoomMember("Member", "Handle", false, "InGame", "", "", "US") { PreferenceKey = key };
            InformationOverlayRoomContent? room = new("room", "Room", "", 4, "", [member], []);
            using var source = new OverlayCommunitySource(() => (owner, 1), new Reader(), false,
                choiceStore: new(root), room: () => room);
            async Task<BridgeEnvelope> Send(string name, object payload, BridgeAccountContext? asOwner = null) =>
                (await source.DispatchRosterAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString(), 1, payload, asOwner ?? owner), default)).Response;
            var saved = await Send("overlayRoster.update", new { schemaVersion = 1, revision = 0, key, mode = "pin" });
            Check(saved.Error is null && source.RosterPreferences.Pinned.Contains(key), "Saved preferences drive runtime snapshot.");
            Check(new OverlaySceneChoiceStore(root).Read(owner).Roster.Pinned.Contains(key), "Restart retains local preferences.");
            Check((await Send("overlayRoster.update", new { schemaVersion = 1, revision = 0, key, mode = "exclude" })).Error is not null,
                "Stale revision cannot overwrite a preference.");
            room = room with { Members = [] };
            var read = await Send("overlayRoster.read", new { schemaVersion = 1 });
            Check(read.Payload.GetProperty("rows").GetArrayLength() == 0, "Revoked pinned member leaves no row or count.");
            Check((await Send("overlayRoster.update", new { schemaVersion = 1, revision = 1, key, mode = "pin" })).Error is not null,
                "Unknown or revoked member cannot be pinned through the bridge.");
            Check((await Send("overlayRoster.read", new { schemaVersion = 1 }, owner with { Subject = "other" })).Error is not null,
                "Wrong account cannot read preferences.");
            room = room with { Members = [member] };
            Check((await Send("overlayRoster.update", new { schemaVersion = 1, revision = 1, key, mode = "exclude" })).Error is null,
                "Visible member may change from pinned to excluded.");
            Check(source.RosterPreferences.Pinned.Length == 0 && source.RosterPreferences.Excluded.Contains(key), "Exclude and pin stay exclusive.");

            // Member-module overflow display rides the same account-local preferences.
            var defaults = (await Send("overlayRoster.read", new { schemaVersion = 1 })).Payload.GetProperty("display");
            Check(defaults.GetProperty("overflow").GetString() == "summary" && defaults.GetProperty("rowLimit").GetInt32() == 0 &&
                  defaults.GetProperty("rotationIntervalSeconds").GetInt32() == 10, "Unset display reads as the defaults.");
            Check(!File.ReadAllText(Directory.GetFiles(Path.Combine(root, "overlay-source-v1"), "*.json").Single()).Contains("rowLimit"),
                "Default display values are not written, so older hosts still read the file.");
            var display = new { overflow = "rotate", rowLimit = 4, rotationIntervalSeconds = 20 };
            Check((await Send("overlayRoster.update", new { schemaVersion = 1, revision = 1, display })).Error is not null,
                "A stale revision cannot change the display.");
            Check((await Send("overlayRoster.update", new { schemaVersion = 1, revision = 2,
                display = new { overflow = "scroll", rowLimit = 4, rotationIntervalSeconds = 20 } })).Error is not null &&
                  (await Send("overlayRoster.update", new { schemaVersion = 1, revision = 2,
                display = new { overflow = "rotate", rowLimit = 13, rotationIntervalSeconds = 20 } })).Error is not null &&
                  (await Send("overlayRoster.update", new { schemaVersion = 1, revision = 2,
                display = new { overflow = "rotate", rowLimit = 4, rotationIntervalSeconds = 3 } })).Error is not null &&
                  (await Send("overlayRoster.update", new { schemaVersion = 1, revision = 2, key, mode = "pin", display })).Error is not null,
                "Unknown modes, out-of-range values and mixed updates are rejected.");
            var shown = await Send("overlayRoster.update", new { schemaVersion = 1, revision = 2, display });
            Check(shown.Error is null && shown.Payload.GetProperty("display").GetProperty("overflow").GetString() == "rotate",
                "The display update answers with the saved options.");
            var stored = new OverlaySceneChoiceStore(root).Read(owner).Roster;
            Check(stored.Overflow == "rotate" && stored.RowLimit == 4 && stored.RotationIntervalSeconds == 20 &&
                  stored.Excluded.Contains(key), "Display options persist next to pins and exclusions.");
            Check(source.RosterPreferences.EffectiveOverflow == "rotate", "The runtime snapshot sees the new display.");
            // Re-save the member's mode (kept as excluded for the account-switch check below).
            Check((await Send("overlayRoster.update", new { schemaVersion = 1, revision = 3, key, mode = "exclude" })).Error is null &&
                  new OverlaySceneChoiceStore(root).Read(owner).Roster is { Overflow: "rotate", RowLimit: 4 },
                "Changing a member's mode keeps the display options.");
            Check((await Send("overlayRoster.update", new { schemaVersion = 1, revision = 4,
                display = new { overflow = "rotate", rowLimit = 4, rotationIntervalSeconds = 10 } })).Error is null &&
                  new OverlaySceneChoiceStore(root).Read(owner).Roster.RotationIntervalSeconds == 0,
                "The default interval is stored as unset.");
            var previousOwner = owner;
            owner = owner with { Subject = "new-account" };
            Check(source.RosterPreferences.Excluded.Length == 0 && new OverlaySceneChoiceStore(root).Read(previousOwner).Roster.Excluded.Contains(key),
                "Account switch isolates preferences without migrating or deleting old state.");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private sealed class Reader : IOverlayCommunityReader
    {
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) => Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) => throw new NotSupportedException();
    }
}
