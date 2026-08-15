using StarBridge.Core.Presence;
using System.Windows;
using MediaBrush = System.Windows.Media.Brush;

namespace StarBridge.Desktop;

internal enum InGameFleetMemberAction
{
    OpenProfile,
    SendMessage
}

internal sealed record InGameFleetMemberRow(
    string? AccountId,
    string Callsign,
    string GameId,
    string? AvatarSource,
    string Initials,
    PlayerPresenceKind Presence,
    string Role,
    bool IsCommander,
    string Ship,
    string Location,
    string Server,
    bool IsSelf,
    bool CanOpenProfile,
    bool CanMessage,
    bool IsSameServer = false,
    MediaBrush? RoleAccent = null,
    bool? HasServerSession = null)
{
    public string PresenceText => PlayerPresencePresentation.Format(Presence);
    public MediaBrush PresenceBrush => PlayerPresencePresentation.Brush(Presence);
    public MediaBrush RoleBrush => RoleAccent ?? (IsCommander
        ? StatusPalette.WarningBrush
        : StatusPalette.InfoBrush);
    public MediaBrush CoordinationBrush => IsSameServer
        ? StatusPalette.SuccessBrush
        : PresenceBrush;
    public string IdentityText => string.IsNullOrWhiteSpace(GameId) ||
                                    Callsign.Equals(GameId, StringComparison.OrdinalIgnoreCase)
        ? Callsign
        : $"{Callsign} · {GameId}";
    public string RoleText => string.IsNullOrWhiteSpace(Role) ? "组织成员" : Role;
    public string ShipText => ShipDisplayNamePresentation.ResolveChinese(
        PlayerSessionStatePresentation.ResolveShip(
            Presence,
            HasServerSession,
            Ship),
        ShipDisplayNamePresentation.UnknownShip);
    public string LocationText => PlayerSessionStatePresentation.ResolveLocation(
        Presence,
        HasServerSession,
        Location);
    public string ServerText => PlayerSessionStatePresentation.ResolveServer(
        Presence,
        HasServerSession,
        Server);
    public string CoordinationText => IsSelf
        ? "你"
        : IsSameServer
            ? "同服务器"
            : PresenceText;
    public string ContextText => string.Join(
        " · ",
        new[] { ShipText, LocationText, ServerText }
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.CurrentCultureIgnoreCase));
}

internal sealed record InGameFleetShipRow(
    int Number,
    string Name,
    string Code,
    string? ImageSource,
    string Owner,
    string Spec,
    string Role,
    string Status,
    string Value,
    bool OwnerIsOnline,
    string? CustomImageMediaId = null,
    string? ShipInstanceId = null,
    string? OwnerAccountId = null,
    bool CanReportCustomImage = false)
{
    public string EnglishName => string.IsNullOrWhiteSpace(Code) ||
                                 Name.Equals(Code, StringComparison.OrdinalIgnoreCase)
        ? ""
        : Code;
    public string IdentityText => string.IsNullOrWhiteSpace(Code) ||
                                    Name.Equals(Code, StringComparison.OrdinalIgnoreCase)
        ? Name
        : $"{Name} · {Code}";
    public string CaptainText => Owner;
    public string OwnerPresenceText => OwnerIsOnline ? "在线" : "离线";
    public MediaBrush OwnerPresenceBrush => OwnerIsOnline
        ? StatusPalette.SuccessBrush
        : StatusPalette.DisabledBrush;
    public string SpecText => string.Join(
        " · ",
        new[] { Spec, Role, Status }
            .Where(value => !string.IsNullOrWhiteSpace(value)));
    public string ValueText => string.IsNullOrWhiteSpace(Value) ? "价值未公布" : Value;
    public Visibility ShipImageReportVisibility => CanReportCustomImage ? Visibility.Visible : Visibility.Collapsed;
}

internal enum InGameFleetShipOwnerFilter
{
    All,
    Online,
    Offline
}

internal static class InGameFleetShipFilter
{
    internal static InGameFleetShipRow[] Apply(
        IEnumerable<InGameFleetShipRow> ships,
        InGameFleetShipOwnerFilter filter) =>
        filter switch
        {
            InGameFleetShipOwnerFilter.Online => ships
                .Where(ship => ship.OwnerIsOnline == true)
                .ToArray(),
            InGameFleetShipOwnerFilter.Offline => ships
                .Where(ship => ship.OwnerIsOnline == false)
                .ToArray(),
            _ => ships.ToArray()
        };
}

internal sealed record InGameFleetSnapshot(
    bool IsAvailable,
    string FleetName,
    string FleetCode,
    string Commander,
    string Description,
    string? LogoSource,
    string AnnouncementTitle,
    string AnnouncementContent,
    int TotalMembers,
    int InGameMembers,
    int OnlineMembers,
    int AwayMembers,
    int OfflineMembers,
    InGameFleetMemberRow[] Members,
    InGameFleetShipRow[] Ships,
    string StatusText,
    string Fingerprint)
{
    internal static InGameFleetSnapshot Unavailable(string statusText) =>
        InGameFleetProjection.Build(
            false,
            "组织面板",
            "",
            "",
            "",
            null,
            "",
            "",
            [],
            [],
            statusText);
}

internal static class InGameFleetProjection
{
    internal static InGameFleetSnapshot Build(
        bool isAvailable,
        string fleetName,
        string fleetCode,
        string commander,
        string description,
        string? logoSource,
        string announcementTitle,
        string announcementContent,
        IEnumerable<InGameFleetMemberRow> members,
        IEnumerable<InGameFleetShipRow> ships,
        string statusText)
    {
        var memberRows = members
            .OrderBy(CoordinationRank)
            .ThenByDescending(member => member.IsSelf)
            .ThenBy(member => PresenceRank(member.Presence))
            .ThenByDescending(member => member.IsCommander)
            .ThenBy(member => member.Callsign, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
        var shipRows = ships
            .OrderBy(ship => ship.Number)
            .ThenBy(ship => ship.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();

        var inGame = memberRows.Count(member => member.Presence == PlayerPresenceKind.InGame);
        var online = memberRows.Count(member => member.Presence == PlayerPresenceKind.AppOnline);
        var away = memberRows.Count(member => member.Presence == PlayerPresenceKind.Away);
        var offline = memberRows.Length - inGame - online - away;
        var fingerprint = BuildFingerprint(
            isAvailable,
            fleetName,
            fleetCode,
            commander,
            description,
            logoSource,
            announcementTitle,
            announcementContent,
            memberRows,
            shipRows,
            statusText);

        return new InGameFleetSnapshot(
            isAvailable,
            fleetName,
            fleetCode,
            commander,
            description,
            logoSource,
            announcementTitle,
            announcementContent,
            memberRows.Length,
            inGame,
            online,
            away,
            offline,
            memberRows,
            shipRows,
            statusText,
            fingerprint);
    }

    private static int PresenceRank(PlayerPresenceKind presence) =>
        presence switch
        {
            PlayerPresenceKind.InGame => 0,
            PlayerPresenceKind.AppOnline => 1,
            PlayerPresenceKind.Away => 2,
            _ => 3
        };

    private static int CoordinationRank(InGameFleetMemberRow member)
    {
        if (member.IsSameServer)
        {
            return 0;
        }

        return member.Presence switch
        {
            PlayerPresenceKind.InGame => 1,
            PlayerPresenceKind.AppOnline => 2,
            PlayerPresenceKind.Away => 3,
            _ => 4
        };
    }

    private static string BuildFingerprint(
        bool isAvailable,
        string fleetName,
        string fleetCode,
        string commander,
        string description,
        string? logoSource,
        string announcementTitle,
        string announcementContent,
        IEnumerable<InGameFleetMemberRow> members,
        IEnumerable<InGameFleetShipRow> ships,
        string statusText)
    {
        var value = new HashCode();
        value.Add(isAvailable);
        AddText(ref value, fleetName);
        AddText(ref value, fleetCode);
        AddText(ref value, commander);
        AddText(ref value, description);
        AddText(ref value, logoSource);
        AddText(ref value, announcementTitle);
        AddText(ref value, announcementContent);
        AddText(ref value, statusText);
        foreach (var member in members)
        {
            AddText(ref value, member.AccountId);
            AddText(ref value, member.Callsign);
            AddText(ref value, member.GameId);
            AddText(ref value, member.AvatarSource);
            AddText(ref value, member.Initials);
            value.Add(member.Presence);
            AddText(ref value, member.Role);
            value.Add(member.IsCommander);
            AddText(ref value, member.Ship);
            AddText(ref value, member.Location);
            AddText(ref value, member.Server);
            value.Add(member.IsSelf);
            value.Add(member.CanOpenProfile);
            value.Add(member.CanMessage);
            value.Add(member.IsSameServer);
            AddText(ref value, member.RoleAccent?.ToString());
        }

        foreach (var ship in ships)
        {
            value.Add(ship.Number);
            AddText(ref value, ship.Name);
            AddText(ref value, ship.Code);
            AddText(ref value, ship.ImageSource);
            AddText(ref value, ship.Owner);
            AddText(ref value, ship.Spec);
            AddText(ref value, ship.Role);
            AddText(ref value, ship.Status);
            AddText(ref value, ship.Value);
            value.Add(ship.OwnerIsOnline);
            AddText(ref value, ship.CustomImageMediaId);
            AddText(ref value, ship.ShipInstanceId);
            AddText(ref value, ship.OwnerAccountId);
            value.Add(ship.CanReportCustomImage);
        }

        return value.ToHashCode().ToString("X8");
    }

    private static void AddText(ref HashCode hash, string? value) =>
        hash.Add(value ?? "", StringComparer.Ordinal);
}

internal sealed class InGameFleetMemberActionRequestedEventArgs(
    InGameFleetMemberRow member,
    InGameFleetMemberAction action) : EventArgs
{
    internal InGameFleetMemberRow Member { get; } = member;
    internal InGameFleetMemberAction Action { get; } = action;
}

internal sealed class InGameFleetShipImageReportRequestedEventArgs(InGameFleetShipRow ship) : EventArgs
{
    internal InGameFleetShipRow Ship { get; } = ship;
}

internal sealed class InGameFleetShipImagePreviewRequestedEventArgs(InGameFleetShipRow ship) : EventArgs
{
    internal InGameFleetShipRow Ship { get; } = ship;
}
