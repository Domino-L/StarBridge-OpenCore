using StarBridge.Core.Friends;

namespace StarBridge.Core.Tests;

internal static class FriendSharingPolicyTests
{
    public static void RunAll()
    {
        var now = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        var source = new FriendSharingSource(now, "InGame", "server-A", "US", "Ship", "Place",
            true, true, true, now.AddMinutes(-1));
        FriendSharedView Project(FriendSharedFields fields, FriendSharingSource? input = null) =>
            FriendSharingPolicy.Project(new(fields), input ?? source, true, false, true, "server-A", now);
        for (var bits = 0; bits <= 63; bits++)
        {
            var fields = (FriendSharedFields)bits;
            var result = Project(fields);
            Require((result.Presence is not null) == fields.HasFlag(FriendSharedFields.Presence), "presence independent");
            Require((result.SameServer is not null) == fields.HasFlag(FriendSharedFields.ServerRelation), "relation independent");
            Require((result.ServerId is not null) == fields.HasFlag(FriendSharedFields.ServerDetails), "server independent");
            Require((result.ServerRegion is not null) == fields.HasFlag(FriendSharedFields.ServerDetails), "region independent");
            Require((result.Ship is not null) == fields.HasFlag(FriendSharedFields.Ship), "ship independent");
            Require((result.Location is not null) == fields.HasFlag(FriendSharedFields.Location), "location independent");
            Require((result.LastOnlineAt is not null) == fields.HasFlag(FriendSharedFields.LastOnline), "last seen independent");
        }
        var relation = Project(FriendSharedFields.ServerRelation);
        Require(Project(FriendSharedFields.Presence, source with { Presence = "Away" }).Presence == "Away",
            "existing away presence remains supported");
        Require(Project(FriendSharedFields.LastOnline, source with { LastOnlineAt = default(DateTimeOffset) }).LastOnlineAt is null,
            "missing historical timestamp is not displayed as year one");
        Require(relation.SameServer == true && relation.ServerId is null && relation.ServerRegion is null,
            "same-server relation never reveals server details");
        Require(FriendSharingPolicy.Project(new(FriendSharedFields.All), source, true, false, true, null, now).SameServer is null,
            "unknown viewer server is not a different-server assertion");
        foreach (var gates in new[] { (false, false, true), (true, true, true), (true, false, false) })
            Require(FriendSharingPolicy.Project(new(FriendSharedFields.All), source, gates.Item1, gates.Item2,
                gates.Item3, "server-A", now) == new FriendSharedView(), "revoked access clears every field");
        Require(FriendSharingPolicy.Project(null, source, true, false, true, "server-A", now) == new FriendSharedView(),
            "missing consent never becomes suggested defaults");
        var stale = Project(FriendSharedFields.All, source with { ObservedAt = now.AddSeconds(-46) });
        Require(stale == new FriendSharedView(LastOnlineAt: source.LastOnlineAt), "expired live evidence retains only authorized last-seen history");
        var offline = Project(FriendSharedFields.All, source with { Presence = "Offline" });
        Require(offline == new FriendSharedView(Presence: "Offline", LastOnlineAt: source.LastOnlineAt), "offline clears stale game details");
        var uncertain = Project(FriendSharedFields.All, source with { ShipConfirmed = false, LocationConfirmed = false });
        Require(uncertain.Ship is null && uncertain.Location is null, "unconfirmed evidence stays private");
        Require(Project(FriendSharedFields.All, source with { LastOnlineAt = now.AddMinutes(1) }).LastOnlineAt is null,
            "future last-seen evidence is rejected");
        foreach (var invalid in new[] { -1, 64, 127 })
        {
            try { new FriendSharingPreferences((FriendSharedFields)invalid).Validate(); }
            catch (ArgumentOutOfRangeException) { continue; }
            throw new InvalidOperationException("Unknown permission bit accepted.");
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
