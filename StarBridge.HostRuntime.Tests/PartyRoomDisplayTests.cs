using System.Buffers.Binary;
using System.Text.Json.Nodes;
using System.Text;
using StarBridge.HostRuntime.PartyRooms;

internal static class PartyRoomDisplayTests
{
    internal static Task Projection()
    {
        const string png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        RoomView Read(string? avatar, string presence = "游戏中 · EPTU", bool host = true)
        {
            var wire = JsonNode.Parse(PartyRoomReaderTests.Wire(null, PartyRoomReaderTests.Room("one")))!;
            var member = wire["rooms"]![0]!["members"]![0]!;
            member["avatarImageData"] = avatar;
            member["presenceText"] = presence;
            member["isHost"] = host;
            return PartyRoomReader.Parse(Encoding.UTF8.GetBytes(wire.ToJsonString())).Rooms.Single();
        }
        foreach (var pair in new[] {
            ("游戏中 · LIVE", "presence.inGame"), ("Playing · EPTU", "presence.inGame"),
            ("应用在线", "presence.online"), ("暫離", "presence.away"),
            ("Offline", "presence.offline"), ("unrecognized private text", "presence.unknown")
        })
            Check(Read(null, pair.Item1).Members.Single().PresenceKey == pair.Item2, "Known viewer-scoped presence has an explicit semantic key.");
        var valid = Read(png);
        Check(valid.Members.Single().AvatarImageData == "data:image/png;base64," + png, "Bounded actual avatar is normalized.");
        Check(valid.LeaderGameVersion == "EPTU", "Only explicit leader presence supplies the game version.");
        Check(Read("data:image/png;base64," + png).Members.Single().AvatarImageData != null, "Existing data URI accepted.");
        foreach (var value in new[] { "private-avatar", "https://example.test/avatar.png", "C:/private/avatar.png", "data:image/svg+xml;base64,PHN2Zz4=", new string('A', 128 * 1024 + 1) })
            Check(Read(value).Members.Single().AvatarImageData is null, "Bad optional avatar falls back without rejecting the room.");
        var enormous = Convert.FromBase64String(png);
        BinaryPrimitives.WriteUInt32BigEndian(enormous.AsSpan(16, 4), 100000);
        Check(Read(Convert.ToBase64String(enormous)).Members.Single().AvatarImageData is null, "Encoded image dimensions are bounded.");
        foreach (var value in new[] { "游戏中", "InGame", "应用在线", "pub_use1b_00000000_001", "LIVE" })
            Check(Read(null, value).LeaderGameVersion == "", "Do not infer a version from region or plain presence.");
        Check(Read(null, "Playing · HOTFIX").LeaderGameVersion == "HOTFIX", "Custom game channels are preserved.");
        Check(Read(null, "游戏中 · LIVE", false).LeaderGameVersion == "", "Another member never substitutes for the host.");
        return Task.CompletedTask;
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
