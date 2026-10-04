using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.Core.PartyRooms;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task RoomAvatarPipeline()
    {
        const string png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        var media = new byte[128 * 1024];
        Convert.FromBase64String(png).CopyTo(media, 0);
        var avatar = "data:image/png;base64," + Convert.ToBase64String(media);
        using var profileTransport = new Transport();
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), profileTransport);
        using var transport = new RoomMediaTransport { PeerAvatar = avatar };
        using var rooms = new PartyRoomReader(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, partyRooms: rooms);
        await host.LoginLegacyAsync(BridgePayload.From(new {
            schemaVersion = 1, email = "old@example.invalid", password = "synthetic"
        }), 0, default);
        var context = host.CurrentContext!;
        var directory = await host.GetPartyRoomsAsync(context, default);
        var peer = directory.Rooms.Single().Members.Single(member => !member.IsHost);
        Check(peer.AvatarImageData == avatar && !peer.IsSelf && peer.UserRef is not null,
            "Actual Host room read must retain the peer's permitted account-size avatar and scoped target.");
        var json = BridgePayload.From(directory).GetRawText();
        Check(!json.Contains("peer-fixture") && !json.Contains("legacy-synthetic"),
            "Internal identities cannot cross the avatar bridge.");
        transport.PeerAvatar = null;
        directory = await host.GetPartyRoomsAsync(context, default);
        Check(directory.Rooms.Single().Members.Single(member => !member.IsHost).AvatarImageData is null,
            "A fresh privacy-redacted avatar cannot fall back to an older peer or the viewer's image.");

        transport.Application = true;
        transport.PeerAvatar = avatar;
        directory = await host.GetPartyRoomsAsync(context, default);
        var applicant = directory.Rooms.Single().PendingApplications.Single();
        Check(applicant.AvatarImageData == avatar && applicant.UserRef is not null,
            "Actual Host application directory carries the permitted image and a host-scoped avatar menu.");
        Check((await host.GetPartyRoomsAsync(context, default)).Rooms.Single().PendingApplications.Single().UserRef == applicant.UserRef,
            "Background refresh preserves the same applicant profile target.");
        await Open(applicant.UserRef!, "applicant-fixture");
        transport.Application = false;
        await Reject(applicant.UserRef!);

        transport.Preview = true;
        directory = await host.GetPartyRoomsAsync(context, default);
        var preview = directory.Rooms.Single().Members.Single(member => !member.IsHost);
        Check(directory.Rooms.Single().CanPreviewMemberProfiles && preview.UserRef is not null && preview.GameId == "",
            "Authorized room discovery uses a scoped target, never game identity.");
        Check((await host.GetPartyRoomsAsync(context, default)).Rooms.Single().Members.Last().UserRef == preview.UserRef,
            "Background refresh preserves the same preview target.");
        await Open(preview.UserRef!, "peer-fixture");
        transport.Password = true;
        await Reject(preview.UserRef!);
        directory = await host.GetPartyRoomsAsync(context, default);
        Check(!directory.Rooms.Single().CanPreviewMemberProfiles && directory.Rooms.Single().Members.All(member =>
            member.UserRef is null && member.AvatarImageData is null), "Locked discovery clears images and targets.");
        transport.Password = false;
        directory = await host.GetPartyRoomsAsync(context, default);
        preview = directory.Rooms.Single().Members.Last();
        transport.ProfileAllowed = false;
        await Reject(preview.UserRef!);

        transport.ProfileAllowed = true;
        directory = await host.GetPartyRoomsAsync(context, default);
        preview = directory.Rooms.Single().Members.Last();
        transport.Eligibility = "invite";
        await Reject(preview.UserRef!);

        async Task Open(string reference, string id)
        {
            profileTransport.Body = JsonSerializer.Serialize(new PersonalProfileDocumentContract(3, id, true, 1,
                DateTimeOffset.UtcNow, new("Fixture", ""), PersonalProfileContentContract.Empty, null, new([]), null),
                new JsonSerializerOptions(JsonSerializerDefaults.Web));
            await host.ReadUserProfileAsync(context, BridgePayload.From(new {
                schemaVersion = 1, source = "room", reference, query = ""
            }), default);
            Check(profileTransport.Path == "/api/profiles/" + id && profileTransport.Authorized,
                "Actual Host room menu opens the exact authorized profile via the existing authenticated endpoint.");
        }

        async Task Reject(string reference)
        {
            var previous = profileTransport.Calls;
            try
            {
                await host.ReadUserProfileAsync(context, BridgePayload.From(new {
                    schemaVersion = 1, source = "room", reference, query = ""
                }), default);
                throw new Exception("Revoked room origin opened a profile.");
            }
            catch (AccountBridgeHostException error)
            { Check(error.Code == "users.targetChanged" && profileTransport.Calls == previous,
                "Authority loss must stop before a profile HTTP read."); }
        }
    }

    private sealed class RoomMediaTransport : HttpMessageHandler
    {
        internal string? PeerAvatar;
        internal bool Application, Preview, Password, ProfileAllowed = true;
        internal string Eligibility = "everyone";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var now = DateTimeOffset.UtcNow;
            var room = new PartyRoomSnapshot("fixture-room", "fixture-code", "legacy-synthetic", "Fixture", "", [], [], 4,
                true, Eligibility, "direct", Password, "recommended", "zh", null, now.AddHours(1),
                [new("", "Viewer", "", null, true, "应用在线", "", "", "", now) { PublicProfileId = "legacy-synthetic" },
                 new("", "Peer", "", PeerAvatar, false, "应用在线", "", "", "", now) { PublicProfileId = ProfileAllowed ? "peer-fixture" : null }],
                now, now, 1) { ViewerIsHost = !Preview, CanPreviewMemberProfiles = Preview,
                    PendingApplications = Application ? [new("fixture-application", "Applicant", "", PeerAvatar, now) {
                        AccountId = "applicant-fixture" }] : [] };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(
                JsonSerializer.Serialize(new PartyRoomDirectoryResponse([room], Preview ? null : room.RoomId, now),
                    new JsonSerializerOptions(JsonSerializerDefaults.Web)), Encoding.UTF8, "application/json") });
        }
    }
}
