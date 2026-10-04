using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class RoomOverlaySessionTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "member-a");
    private static readonly DateTimeOffset Start = new(2026, 9, 6, 12, 0, 0, TimeSpan.Zero);
    private static RoomDirectoryView Directory(string? current = "room", string title = "Room") =>
        new(current, Start, [new("room", title, "Goal", 4, true, "any", "direct", false,
            "none", "en", Start.AddHours(1), null, true,
            [new("Callsign", "Case_Handle", true, "InGame", "", "", "pub_use1b_12345_070") { IsSelf = true }])]);
    private static RoomChatMessageView Message(long sequence, string text = "hello") =>
        new(sequence, $"m-{sequence}", "text", "Callsign", "Case_Handle", text, Start, null);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    internal static Task Membership()
    {
        var session = new RoomOverlaySession(() => Start);
        Check(!session.ReadPresetTrigger(Owner, 1).Known, "Unknown membership cannot trigger a preset change.");
        session.ApplyDirectory(Owner, 1, Directory(null), "Case_Handle");
        Check(session.ReadPresetTrigger(Owner, 1) == (true, null), "A confirmed lobby is a known preset trigger.");
        Check(session.Read(Owner, 1) is null, "Browsing is not membership.");
        session.ApplyDirectory(Owner, 1, Directory(), "Case_Handle");
        Check(session.ReadPresetTrigger(Owner, 1) == (true, "room"), "Confirmed room supplies its exact identity.");
        Check(!session.ReadPresetTrigger(Owner, 2).Known &&
            !session.ReadPresetTrigger(Owner with { Subject = "other" }, 1).Known,
            "Preset triggers never cross account or session generation.");
        var content = session.Read(Owner, 1)!;
        Check(content.Members.Single().GameId == "Case_Handle", "Preserve handle casing.");
        Check(content.Members.Single().IsSelf == true, "Preserve authenticated self identity for local-only overlay display.");
        Check(content.Members.Single().ServerRegion == "US", "Expose region, never full shard.");
        Check(content.Members.Single().Location == "" && content.Members.Single().Ship == "",
            "Do not fill privacy-redacted fields from local state.");
        var arriving = Directory();
        arriving.Rooms[0].Members[0] = arriving.Rooms[0].Members[0] with
        { LocationText = "Previous Port", ArrivalPendingConfirmation = true, ArrivalTargetCode = "Current Target" };
        session.ApplyDirectory(Owner, 1, arriving, "Case_Handle");
        Check(session.Read(Owner, 1)!.Members.Single() is
            { ArrivalPendingConfirmation: true, ArrivalTargetCode: "Current Target", Location: "Previous Port" },
            "Room source preserves arrival target separately from prior confirmed place for Native");
        session.ApplyDirectory(Owner, 1, Directory(null), "Case_Handle");
        Check(session.Read(Owner, 1) is null, "Leaving drops room content.");
        Check(session.ReadPresetTrigger(Owner, 1) == (true, null), "Confirmed leave can restore the previous preset.");
        return Task.CompletedTask;
    }

    internal static Task Revocation()
    {
        var now = Start;
        var session = new RoomOverlaySession(() => now);
        var confirmations = 0;
        session.MembershipConfirmed += (_, _, _) => confirmations++;
        var changes = 0;
        session.ContentChanged += () => changes++;
        void Join() => session.ApplyDirectory(Owner, 1, Directory(), "Case_Handle");
        Join(); Check(session.Read(Owner with { Subject = "other" }, 1) is null, "No account crossing.");
        Join(); Check(session.Read(Owner, 2) is null, "No generation crossing.");
        Join(); Check(session.Read(null, 1) is null, "Signed-out/invalid credentials clear.");
        Join(); changes = 0; session.Clear();
        Check(changes == 1 && session.Read(Owner, 1) is null, "Authority/protocol invalidation notifies the native sink immediately.");
        session.Clear(); Check(changes == 1, "Repeated empty clears do not cause a refresh loop.");
        Join(); now = Start.AddSeconds(29);
        var authority = session.PeekAuthority(Owner, 1);
        var beforeProbe = changes;
        Check(authority is not null && session.PeekAuthority(Owner with { Subject = "other" }, 1) is null &&
            session.PeekAuthority(Owner, 2) is null && changes == beforeProbe,
            "Pure room probes reject other accounts without clearing or notifying the active room.");
        Check(session.Read(Owner, 1) is not null, "Reading still-valid content does not create a new lease.");
        now = Start.AddSeconds(30);
        Check(session.PeekAuthority(Owner, 1) is null && changes == beforeProbe,
            "Expired room probes fail closed without mutating runtime state.");
        var beforeExpiry = confirmations;
        Check(session.Read(Owner, 1) is null, "Stopped polling expires content.");
        Check(!session.ReadPresetTrigger(Owner, 1).Known, "Expired display data is not a preset leave trigger.");
        Check(confirmations == beforeExpiry, "Expiry clears authorization but is not a confirmed membership exit.");
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
        session.ApplyChat("room", null, Message(103, "") with
        {
            Attachment = new(StarBridge.Core.Chat.ChatAttachmentKinds.OverlayPreset,
                "Shared layout", "Layout", "{\"Version\":1,\"Name\":\"Layout\",\"Settings\":\"settings\",\"Layout\":\"layout\"}")
        }, false);
        Check(session.Read(Owner, 1)!.Messages.Count == 1,
            "An attachment-only live message must reach the overlay, without downloading its payload.");
        Check(session.Read(Owner, 1)!.Messages.Single().AttachmentKind == "overlay_preset",
            "Pass the attachment kind, not private package details, to the renderer.");
        return Task.CompletedTask;
    }
}
