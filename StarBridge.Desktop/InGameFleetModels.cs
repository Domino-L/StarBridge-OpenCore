using StarBridge.Core.Presence;
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
    string SquadName,
    string Ship,
    string Location,
    string Server,
    bool IsSelf,
    bool CanOpenProfile,
    bool CanMessage,
    bool IsSameServer = false,
    bool IsCurrentUserSquad = false,
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
        : IsCurrentUserSquad
            ? StatusPalette.WarningBrush
            : PresenceBrush;
    public string IdentityText => string.IsNullOrWhiteSpace(GameId) ||
                                    Callsign.Equals(GameId, StringComparison.OrdinalIgnoreCase)
        ? Callsign
        : $"{Callsign} · {GameId}";
    public string RoleText => string.IsNullOrWhiteSpace(Role) ? "舰队成员" : Role;
    public string SquadText => string.IsNullOrWhiteSpace(SquadName) ||
                                  SquadName.Equals("Unassigned", StringComparison.OrdinalIgnoreCase)
        ? "未加入小队"
        : SquadName;
    public string ShipText => PlayerSessionStatePresentation.ResolveShip(
        Presence,
        HasServerSession,
        Ship);
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
            : IsCurrentUserSquad
                ? "我的小队"
                : PresenceText;
    public string ContextText => string.Join(
        " · ",
        new[] { SquadText, ShipText, LocationText, ServerText }
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.CurrentCultureIgnoreCase));
}

internal sealed record InGameFleetSquadRow(
    string Id,
    string Name,
    string Icon,
    string? EmblemSource,
    string Commander,
    string Type,
    string Description,
    int MemberCount,
    int OnlineCount,
    string MemberNames,
    InGameFleetMemberRow[] Members,
    bool IsCurrentUserSquad)
{
    public int InGameCount => Members.Count(member =>
        member.Presence == PlayerPresenceKind.InGame);
    public string CountText => $"{OnlineCount} / {MemberCount} 在线";
    public string InGameCountText => $"{InGameCount} 人游戏中";
    public string CommanderText => $"指挥官 · {Commander}";
    public string TypeText => string.IsNullOrWhiteSpace(Type) ? "类型待补充" : Type;
    public MediaBrush StateBrush => OnlineCount > 0
        ? StatusPalette.SuccessBrush
        : StatusPalette.DisabledBrush;
}

internal sealed record InGameFleetShipRow(
    int Number,
    string Name,
    string Code,
    string? ImageSource,
    string Owner,
    string Squad,
    string Spec,
    string Role,
    string Status,
    string Value,
    bool OwnerIsOnline)
{
    public string EnglishName => string.IsNullOrWhiteSpace(Code) ||
                                 Name.Equals(Code, StringComparison.OrdinalIgnoreCase)
        ? ""
        : Code;
    public string IdentityText => string.IsNullOrWhiteSpace(Code) ||
                                    Name.Equals(Code, StringComparison.OrdinalIgnoreCase)
        ? Name
        : $"{Name} · {Code}";
    public string CaptainText => string.IsNullOrWhiteSpace(Squad) ||
                                   Squad.Equals("Unassigned", StringComparison.OrdinalIgnoreCase)
        ? Owner
        : $"{Owner} / {Squad}";
    public string OwnerPresenceText => OwnerIsOnline ? "在线" : "离线";
    public MediaBrush OwnerPresenceBrush => OwnerIsOnline
        ? StatusPalette.SuccessBrush
        : StatusPalette.DisabledBrush;
    public string SpecText => string.Join(
        " · ",
        new[] { Spec, Role, Status }
            .Where(value => !string.IsNullOrWhiteSpace(value)));
    public string ValueText => string.IsNullOrWhiteSpace(Value) ? "价值未公布" : Value;
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
    InGameFleetSquadRow[] Squads,
    InGameFleetShipRow[] Ships,
    string StatusText,
    string Fingerprint)
{
    internal static InGameFleetSnapshot Unavailable(string statusText) =>
        InGameFleetProjection.Build(
            false,
            "舰队面板",
            "",
            "",
            "",
            null,
            "",
            "",
            [],
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
        IEnumerable<InGameFleetSquadRow> squads,
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
        var squadRows = squads
            .OrderByDescending(squad => squad.IsCurrentUserSquad)
            .ThenByDescending(squad => squad.OnlineCount)
            .ThenBy(squad => squad.Name, StringComparer.CurrentCultureIgnoreCase)
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
            squadRows,
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
            squadRows,
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

        if (member.IsCurrentUserSquad &&
            PlayerPresence.IsOnline(member.Presence))
        {
            return 1;
        }

        return member.Presence switch
        {
            PlayerPresenceKind.InGame => 2,
            PlayerPresenceKind.AppOnline => 3,
            PlayerPresenceKind.Away => 4,
            _ => 5
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
        IEnumerable<InGameFleetSquadRow> squads,
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
            AddText(ref value, member.SquadName);
            AddText(ref value, member.Ship);
            AddText(ref value, member.Location);
            AddText(ref value, member.Server);
            value.Add(member.IsSelf);
            value.Add(member.CanOpenProfile);
            value.Add(member.CanMessage);
            value.Add(member.IsSameServer);
            value.Add(member.IsCurrentUserSquad);
            AddText(ref value, member.RoleAccent?.ToString());
        }

        foreach (var squad in squads)
        {
            AddText(ref value, squad.Id);
            AddText(ref value, squad.Name);
            AddText(ref value, squad.EmblemSource);
            AddText(ref value, squad.Commander);
            AddText(ref value, squad.Type);
            AddText(ref value, squad.Description);
            value.Add(squad.MemberCount);
            value.Add(squad.OnlineCount);
            AddText(ref value, squad.MemberNames);
            foreach (var member in squad.Members)
            {
                AddText(ref value, member.AccountId);
                AddText(ref value, member.Callsign);
                AddText(ref value, member.GameId);
                value.Add(member.Presence);
            }
            value.Add(squad.IsCurrentUserSquad);
        }

        foreach (var ship in ships)
        {
            value.Add(ship.Number);
            AddText(ref value, ship.Name);
            AddText(ref value, ship.Code);
            AddText(ref value, ship.ImageSource);
            AddText(ref value, ship.Owner);
            AddText(ref value, ship.Squad);
            AddText(ref value, ship.Spec);
            AddText(ref value, ship.Role);
            AddText(ref value, ship.Status);
            AddText(ref value, ship.Value);
            value.Add(ship.OwnerIsOnline);
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
