using System.Text.Json;
using StarBridge.Core.Events;

namespace StarBridge.Core.Tests;

internal static class SharedEventPreferencesTests
{
    public static void RunAll()
    {
        Check(SharedActivityEvent.Category("GameStarted") == SharedActivityEventTypes.Presence, "game lifecycle maps to presence events");
        Check(SharedActivityEvent.Category("ServerLeft") == SharedActivityEventTypes.Server, "server events remain independent");
        Check(SharedActivityEvent.Category("PlayerOnline") == 0 && SharedActivityEvent.Category("PlayerShipControlSignal") == 0,
            "identity detection and raw control signals are not shareable events");
        var now = DateTimeOffset.UnixEpoch.AddDays(100);
        Check(!new SharedActivityEvent("unused", "GameStarted", now.AddMinutes(-3)).IsFresh(now), "old events expire");
        Check(!new SharedActivityEvent("unused", "GameStarted", now.AddSeconds(16)).IsFresh(now), "future events rejected");
        Check((int)SharedActivityEventTypes.All == 47, "S2 bits remain stable; retired bit is excluded");
        var joined = DateTimeOffset.UnixEpoch.AddDays(10);
        var selected = new SharedEventChoice(true, SharedActivityEventTypes.Ship | SharedActivityEventTypes.Life);
        var rows = new[] { new CommunityEventChoice("A", joined, selected),
            new CommunityEventChoice("B", joined, SharedEventChoice.Unconfirmed) };
        var preferences = new SharedEventPreferences(SharedEventChoice.Unconfirmed, rows).ValidatedCopy();
        rows[0] = rows[0] with { Choice = SharedEventChoice.Unconfirmed };
        Check(preferences.ResolveCommunity("a", joined, true, true) == selected.SelectedTypes, "copy owns scope array");
        Check(preferences.ResolveCommunity("B", joined, true, true) == 0, "one organization does not grant another");
        Check(preferences.ResolveCommunity("A", joined.AddSeconds(1), true, true) == 0, "rejoining needs fresh consent");
        Check(preferences.ResolveCommunity("A", joined, false, true) == 0, "removed recipient is denied");
        Check(preferences.ResolveCommunity("A", joined, true, false) == 0, "global publication gate wins");
        Check(preferences.ResolveRoom(true, true) == 0, "organization grant never opens room");
        var disabled = selected with { Enabled = false };
        Check(disabled.EffectiveTypes == 0 && disabled.SelectedTypes == selected.SelectedTypes, "disable preserves choices");
        Check((disabled with { Enabled = true }).EffectiveTypes == selected.SelectedTypes, "reenable restores choices");
        var room = preferences with { Room = selected };
        Check(room.ResolveRoom(false, true) == 0 && room.ResolveRoom(true, false) == 0, "room requires both gates");
        Check(room.ResolveRoom(true, true) == selected.SelectedTypes, "room uses own selection");
        Check(SharedEventPreferences.Unconfirmed.ResolveRoom(true, true) == 0, "absent preferences never grant access");
        var json = JsonSerializer.Serialize(preferences);
        var roundTrip = JsonSerializer.Deserialize<SharedEventPreferences>(json)!.ValidatedCopy();
        Check(roundTrip.ResolveCommunity("A", joined, true, true) == selected.SelectedTypes, "serialization preserves consent");
        Reject(() => (selected with { SelectedTypes = (SharedActivityEventTypes)16 }).Validate());
        Reject(() => (selected with { SelectedTypes = (SharedActivityEventTypes)(-1) }).Validate());
        Reject(() => (preferences with { Communities = [preferences.Communities[0], preferences.Communities[0] with { Code = "a" }] }).ValidatedCopy());
        Reject(() => (preferences with { Communities = [preferences.Communities[0] with { JoinedAt = default }] }).ValidatedCopy());
        Reject(() => (preferences with { Communities = [preferences.Communities[0] with { Code = " A" }] }).ValidatedCopy());
        Reject(() => (preferences with { Communities = Enumerable.Range(0, 65).Select(i => new CommunityEventChoice("C" + i, joined, selected)).ToArray() }).ValidatedCopy());
        Check(SharedEventChoice.Normalize((SharedActivityEventTypes)63) == SharedActivityEventTypes.All, "legacy normalization drops retired bit");
    }

    private static void Check(bool value, string reason)
    { if (!value) throw new InvalidOperationException(reason); }
    private static void Reject(Action action)
    {
        try { action(); } catch (ArgumentException) { return; }
        throw new InvalidOperationException("Invalid event preference accepted.");
    }
}
