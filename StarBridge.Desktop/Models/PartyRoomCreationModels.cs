using System.Security.Cryptography;

namespace StarBridge.Desktop;

public enum PartyRoomEligibility
{
    Everyone,
    HostFriends,
    SameFleet,
    InviteOnly
}

public enum PartyRoomLanguage
{
    Chinese,
    English,
    Bilingual
}


public sealed record PartyRoomDisplayTag(
    string Id,
    string CategoryId,
    string Text,
    bool IsPrimary,
    string Foreground,
    string Background,
    string BorderBrush);

public static class PartyRoomTagPresentation
{
    private const string NeutralForeground = "#8DA3B1";
    private const string NeutralBackground = "#0E1821";
    private const string NeutralBorder = "#273B48";

    private static readonly IReadOnlyDictionary<string, TagPalette> GameplayRootPalettes =
        new Dictionary<string, TagPalette>(StringComparer.OrdinalIgnoreCase)
        {
            ["combat"] = new("#FF9AA2", "#321D25", "#85434D"),
            ["industry"] = new("#F2CA68", "#302816", "#78622E"),
            ["logistics"] = new("#8BBEFF", "#18283A", "#45688D"),
            ["support"] = new("#75D9A3", "#173024", "#3D795B"),
            ["exploration"] = new("#6FD5E7", "#142D34", "#3C7280"),
            ["arena"] = new("#C09CF4", "#292039", "#674F8C"),
            ["social"] = new("#F0A7D4", "#30202D", "#76506C"),
            ["special"] = new("#FFB878", "#34251A", "#835D3E")
        };

    private static readonly TagPalette FallbackGameplayPalette =
        new("#B8C5CE", "#222C34", "#50616D");

    public static IReadOnlyList<PartyRoomDisplayTag> Create(
        IEnumerable<string>? gameplayTagNodeIds,
        IEnumerable<string>? contextTagIds)
    {
        var gameplayPaths = (gameplayTagNodeIds ?? [])
            .Select(PartyRoomTagCatalog.GetGameplayPath)
            .Where(path => path.Count > 0)
            .ToArray();
        var result = new List<PartyRoomDisplayTag>();
        var addedIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var path in gameplayPaths)
        {
            var selected = path[^1];
            if (addedIds.Add(selected.Id))
            {
                result.Add(CreateGameplay(path));
            }
        }

        foreach (var id in contextTagIds ?? [])
        {
            if (addedIds.Add(id) && PartyRoomTagCatalog.TryGetContextTag(id, out var tag))
            {
                result.Add(CreateSecondary(tag.Id, tag.Name));
            }
        }

        return result;
    }

    private static PartyRoomDisplayTag CreateGameplay(IReadOnlyList<PartyRoomTagNode> path)
    {
        var root = path[0];
        var palette = GameplayRootPalettes.GetValueOrDefault(root.Id, FallbackGameplayPalette);

        return new(
            path[^1].Id,
            root.Id.ToLowerInvariant(),
            string.Join(" · ", path.Select(node => node.Name)),
            true,
            palette.Foreground,
            palette.Background,
            palette.Border);
    }

    private static PartyRoomDisplayTag CreateSecondary(string id, string text) =>
        new(id, "other", text, false, NeutralForeground, NeutralBackground, NeutralBorder);

    private sealed record TagPalette(string Foreground, string Background, string Border);
}

public sealed record PartyRoomCreateDraft(
    string Title,
    string Goal,
    IReadOnlyList<string> GameplayTagNodeIds,
    IReadOnlyList<string> ContextTagIds,
    int Capacity,
    bool IsPublic,
    PartyRoomEligibility Eligibility,
    PartyLobbyAdmissionMode AdmissionMode,
    bool PasswordEnabled,
    string Password,
    PartyLobbyVoiceRequirement VoiceRequirement,
    PartyRoomLanguage Language,
    int? RecruitmentDurationMinutes,
    int AutoDisbandHours);

public sealed record PartyRoomCreationResult(
    PartyLobbyRoomCard? Room,
    IReadOnlyList<string> Errors)
{
    public bool IsSuccess => Room is not null && Errors.Count == 0;
}

public static class PartyRoomCreation
{
    public static PartyRoomCreationResult Create(
        PartyRoomCreateDraft draft,
        PartyLobbyMemberPreview host,
        DateTimeOffset now)
    {
        var title = draft.Title.Trim();
        var goal = draft.Goal.Trim();
        var gameplayIds = draft.GameplayTagNodeIds
            .Select(PartyRoomTagCatalog.NormalizeGameplayId)
            .Where(id => PartyRoomTagCatalog.TryGetGameplayNode(id, out _))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var contextIds = draft.ContextTagIds
            .Where(id => PartyRoomTagCatalog.TryGetContextTag(id, out _))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var errors = Validate(draft, title, goal, gameplayIds, contextIds);
        if (errors.Count > 0)
        {
            return new(null, errors);
        }

        var tags = gameplayIds
            .Select(PartyRoomTagCatalog.GetCompactGameplayText)
            .Concat(contextIds.Select(id => PartyRoomTagCatalog.TryGetContextTag(id, out var tag) ? tag.Name : id))
            .ToArray();
        var hostDisplay = string.IsNullOrWhiteSpace(host.GameId) ||
                          host.Callsign.Equals(host.GameId, StringComparison.OrdinalIgnoreCase)
            ? host.Callsign
            : $"{host.Callsign} ({host.GameId})";
        var room = new PartyLobbyRoomCard(
            Guid.NewGuid().ToString("N"),
            title,
            goal,
            hostDisplay,
            PartyRoomTagCatalog.GetGameplayRootName(gameplayIds[0]),
            tags,
            1,
            draft.Capacity,
            draft.VoiceRequirement,
            draft.AdmissionMode,
            draft.IsPublic,
            draft.PasswordEnabled,
            [host with { IsHost = true }],
            now)
        {
            RoomCode = Convert.ToHexString(RandomNumberGenerator.GetBytes(3)),
            Eligibility = draft.Eligibility,
            Language = draft.Language,
            RecruitmentClosesAt = draft.RecruitmentDurationMinutes.HasValue
                ? now.AddMinutes(draft.RecruitmentDurationMinutes.Value)
                : null,
            ExpiresAt = now.AddHours(draft.AutoDisbandHours),
            GameplayTagNodeIds = gameplayIds,
            ContextTagIds = contextIds,
            TagCatalogVersion = PartyRoomTagCatalog.Version
        };

        return new(room, []);
    }

    private static List<string> Validate(
        PartyRoomCreateDraft draft,
        string title,
        string goal,
        IReadOnlyList<string> gameplayIds,
        IReadOnlyList<string> contextIds)
    {
        var errors = new List<string>();
        if (title.Length is < 2 or > 32)
        {
            errors.Add("房间名需要 2–32 个字符。");
        }

        if (goal.Length > 120)
        {
            errors.Add("组队目标最多 120 个字符。");
        }

        if (gameplayIds.Count is < 1 or > 3)
        {
            errors.Add("请选择 1–3 条玩法路径。");
        }
        else if (gameplayIds.SelectMany((id, index) => gameplayIds.Skip(index + 1)
                     .Select(other => PartyRoomTagCatalog.AreOnSameBranch(id, other)))
                 .Any(onSameBranch => onSameBranch))
        {
            errors.Add("同一玩法路径不能同时选择父级和子级。");
        }

        if (contextIds.Count > 3 || gameplayIds.Count + contextIds.Count > 5)
        {
            errors.Add("附加标签最多 3 个，全部标签合计最多 5 个。");
        }

        if (draft.Capacity is < 2 or > 16)
        {
            errors.Add("人数上限需要在 2–16 人之间。");
        }

        if (draft.PasswordEnabled && draft.Password.Trim().Length is < 4 or > 32)
        {
            errors.Add("房间密码需要 4–32 个字符。");
        }

        if (draft.RecruitmentDurationMinutes is <= 0)
        {
            errors.Add("招募时长必须大于 0，或选择不限时。");
        }

        if (draft.AutoDisbandHours is not (1 or 2 or 4 or 6 or 12 or 24))
        {
            errors.Add("请选择有效的自动解散时间。");
        }

        if (draft.RecruitmentDurationMinutes.HasValue &&
            draft.RecruitmentDurationMinutes.Value > draft.AutoDisbandHours * 60)
        {
            errors.Add("招募截止时间不能晚于房间自动解散时间。");
        }

        return errors;
    }
}
