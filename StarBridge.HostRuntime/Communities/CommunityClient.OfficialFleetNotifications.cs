using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.Core.FleetChat;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal async Task<CommunityNotificationFeed> ReadScmNotificationsWithOfficialAsync(
        string bearer, string scope, Action current, CancellationToken token)
    {
        CommunityNotificationFeed? communities = null;
        Exception? communityFailure = null;
        try { communities = await ReadScmNotificationsAsync(bearer, scope, current, token); }
        catch (Exception error) when (error is AccountBridgeHostException or HttpRequestException) { communityFailure = error; }
        current(); token.ThrowIfCancellationRequested();
        CommunityNotificationSource? official = null;
        try { official = await ReadOfficialFleetNotificationAsync(bearer, scope, current, token); }
        catch (Exception error) when (error is AccountBridgeHostException or HttpRequestException) { }
        current(); token.ThrowIfCancellationRequested();
        // Independent domains keep their own baselines. A missing official
        // service must not silence valid community delivery (or vice versa).
        if (communities is null && official is null) throw communityFailure ?? Invalid();
        var membership = OfficialNotificationMembership(scope);
        return new(_targetClock.GetUtcNow(), [.. communities?.Sources ?? [], .. official is null ? Array.Empty<CommunityNotificationSource>() : [official]],
            CommunitiesConfirmed: communities is not null, OfficialMembershipConfirmed: membership.Known,
            OfficialMembershipSource: membership.Source);
    }

    internal async Task<CommunityNotificationSource> ReadOfficialFleetNotificationAsync(
        string bearer, string scope, Action current, CancellationToken token)
    {
        try { return await ReadOfficialFleetNotificationCore(bearer, scope, current, token); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or InvalidDataException)
        { throw Invalid(); }
    }

    private async Task<CommunityNotificationSource> ReadOfficialFleetNotificationCore(
        string bearer, string scope, Action current, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(scope)) throw Invalid();
        current(); token.ThrowIfCancellationRequested();
        var context = await OfficialNotificationContext(bearer, scope, current, token);
        var code = context.Source.ToUpperInvariant();
        CommunityNotificationChat? chat = null;
        try {
        var channel = FleetChatIdentity.FleetChannelId(code);
        var channels = await WorkspaceJson(bearer, "/api/official-fleets/chat/channels?fleetCode=" + Uri.EscapeDataString(code), token);
        current(); token.ThrowIfCancellationRequested();
        var unread = NotificationChannelUnread(channels, channel);
        var page = await WorkspaceJson(bearer, "/api/official-fleets/chat/messages?fleetCode=" + Uri.EscapeDataString(code) +
            "&channelId=" + Uri.EscapeDataString(channel) + "&limit=1&projection=client", token);
        current(); token.ThrowIfCancellationRequested();
        if (!Text(page, "channelId", 272).Equals(channel, StringComparison.Ordinal)) throw Invalid();
        // Membership permits the message preview, not publication of archived
        // author identity. G1 author visibility is a separate permission seam.
        chat = NotificationChat(page, unread, includeCallsign: false);
        } catch (Exception e) when (e is AccountBridgeHostException or HttpRequestException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) { }
        var announcements = await NotificationAnnouncements(bearer, code, false, true, current, token);
        var fresh = await OfficialNotificationContext(bearer, scope, current, token);
        if (fresh.Source != context.Source || fresh.Identity != context.Identity) throw new AccountBridgeHostException("communities.notAllowed");
        current(); token.ThrowIfCancellationRequested();
        var key = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new { kind = "officialFleet", scope, source = context.Source, membership = context.Identity }))).ToLowerInvariant();
        return new(key, fresh.Name, null, chat != null, chat, false, [], NotificationPolicyStore.OfficialFleet(context.Source),
            SourceKind: OrganizationNotificationSourceKind.OfficialFleet, Announcements: announcements,
            AnnouncementSource: announcements == null ? null : context.Source, AnnouncementIdentity: context.Source);
    }

    private async Task<(string Source, string Name, string Identity)> OfficialNotificationContext(string bearer, string scope, Action current, CancellationToken token)
    {
        JsonElement body;
        try { body = await WorkspaceJson(bearer, "/api/official-fleets/context", token); }
        catch (AccountBridgeHostException error) when (error.Code is "communities.notAllowed" or "communities.notFound") {
            current(); token.ThrowIfCancellationRequested();
            ObserveOfficialNotificationMembership(scope, null, out _);
            throw;
        }
        current(); token.ThrowIfCancellationRequested();
        if (Number(body, "schemaVersion", 1, 1) != 1 || !body.GetProperty("chatAvailable").GetBoolean() ||
            body.GetProperty("canManageAnnouncements").GetBoolean()) throw Invalid();
        var source = Text(body, "sourceRef", 64);
        _ = NotificationPolicyStore.OfficialFleet(source);
        if (Text(body, "fleetCode", 64) != source.ToUpperInvariant()) throw Invalid();
        var name = Text(body, "name", 256);
        if (string.IsNullOrWhiteSpace(name) || name.Any(char.IsControl)) throw Invalid();
        return (source, name, ObserveOfficialNotificationMembership(scope, source, out _));
    }
}
