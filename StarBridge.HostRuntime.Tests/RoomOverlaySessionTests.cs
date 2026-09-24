using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class RoomOverlaySessionTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "member-a");
    private static readonly DateTimeOffset Start = new(2026, 9, 6, 12, 0, 0, TimeSpan.Zero);
    private static RoomDirectoryView Directory(string? current = "room", string title = "Room") =>
        new(current, Start, [new("room", title, "Goal", 4, true, "any", "direct", false,
            "none", "en", Start.AddHours(1), null, true,
            [new("Callsign", "Case_Handle", true, "InGame", "", "", "pub_use1b_12345_070")])]);
    private static RoomChatMessageView Message(long sequence, string text = "hello") =>
        new(sequence, $"m-{sequence}", "text", "Callsign", "Case_Handle", text, Start, null);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    internal static Task Membership()
    {
        var session = new RoomOverlaySession(() => Start);
        session.ApplyDirectory(Owner, 1, Directory(null), "Case_Handle");
        Check(session.Read(Owner, 1) is null, "Browsing is not membership.");
        session.ApplyDirectory(Owner, 1, Directory(), "Case_Handle");
        var content = session.Read(Owner, 1)!;
        Check(content.Members.Single().GameId == "Case_Handle", "Preserve handle casing.");
        Check(content.Members.Single().ServerRegion == "US", "Expose region, never full shard.");
        Check(content.Members.Single().Location == "" && content.Members.Single().Ship == "",
            "Do not fill privacy-redacted fields from local state.");
        session.ApplyDirectory(Owner, 1, Directory(null), "Case_Handle");
        Check(session.Read(Owner, 1) is null, "Leaving drops room content.");
        return Task.CompletedTask;
    }

    internal static Task Revocation()
    {
        var now = Start;
        var session = new RoomOverlaySession(() => now);
        void Join() => session.ApplyDirectory(Owner, 1, Directory(), "Case_Handle");
        Join(); Check(session.Read(Owner with { Subject = "other" }, 1) is null, "No account crossing.");
        Join(); Check(session.Read(Owner, 2) is null, "No generation crossing.");
        Join(); Check(session.Read(null, 1) is null, "Signed-out/invalid credentials clear.");
        Join(); session.Clear(); Check(session.Read(Owner, 1) is null, "Failed read clears immediately.");
        Join(); now = Start.AddSeconds(30);
        Check(session.Read(Owner, 1) is null, "Stopped polling expires content.");
        session.ApplyDirectory(Owner, 1, Directory() with { ServerTime = Start.AddHours(2) }, "Case_Handle");
        Check(session.Read(Owner, 1) is null, "Expired server room is not rendered.");
        return Task.CompletedTask;
    }

    internal static Task Chat()
    {
        var session = new RoomOverlaySession(() => Start);
        session.ApplyDirectory(Owner, 1, Directory(), "Case_Handle");
        session.ApplyChat("room", new([Message(1)], 1, false, 1), null, false);
        Check(session.Read(Owner, 1)!.Messages.Count == 0, "History is only a baseline.");
        session.ApplyChat("other", new([Message(2)], 2, false, 2), null, false);
        session.ApplyChat("room", new([Message(2)], 2, false, 2), null, true);
        Check(session.Read(Owner, 1)!.Messages.Count == 0, "No other room or history insertion.");
        session.ApplyChat("room", new([Message(2)], 2, false, 2), null, false);
        session.ApplyChat("room", null, Message(2), false);
        session.ApplyDirectory(Owner, 1, Directory(title: "Updated"), "Case_Handle");
        Check(session.Read(Owner, 1)!.Messages.Count == 1, "Refresh preserves live content and deduplicates sends.");
        session.ApplyChat("room", new(Enumerable.Range(3, 100).Select(i => Message(i)).ToArray(), 102, false, 3), null, false);
        Check(session.Read(Owner, 1)!.Messages.Count == 50, "Bound memory to 50 live messages.");
        session.Clear();
        session.ApplyDirectory(Owner, 1, Directory(), "Case_Handle");
        session.ApplyChat("room", new([Message(102)], 102, false, 102), null, false);
        Check(session.Read(Owner, 1)!.Messages.Count == 0, "Recovery establishes a fresh baseline, no replay.");
        return Task.CompletedTask;
    }
}
