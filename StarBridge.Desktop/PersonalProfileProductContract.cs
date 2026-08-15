namespace StarBridge.Desktop;

internal sealed record PersonalProfilePublicFleetAffiliation(
    string FleetName,
    string FleetCode,
    string? FleetLogoAssetId,
    string PositionTitle,
    string? PositionColor)
{
    public static PersonalProfilePublicFleetAffiliation None { get; } = new(
        "未加入组织",
        "",
        null,
        "",
        null);
}

internal sealed record PersonalProfileV2MigrationPreview(
    PersonalProfileModuleSetting[] DisplayedModules,
    string[] OverflowModuleIds)
{
    public int OccupiedCells => DisplayedModules.Sum(module => module.Span);
}

/// <summary>
/// Personal Profile V2 product rules. Phase 0 records the public boundary and
/// migration target without rewriting the user's existing nine-cell layout.
/// </summary>
internal static class PersonalProfileProductContract
{
    public const int LayoutVersion = 2;
    public const int ColumnCount = 3;
    public const int TargetVisibleCellCount = 6;
    public const int MaxVisibleModuleCount = 4;
    public const int LegacyCellCount = 9;

    public static readonly IReadOnlySet<string> FixedSectionIds = new HashSet<string>(StringComparer.Ordinal)
    {
        "identity",
        "fleet-affiliation",
        "availability",
        "introduction"
    };

    public static readonly IReadOnlySet<string> LegacyModulesMovedToFixedSections = new HashSet<string>(StringComparer.Ordinal)
    {
        "fleet-identity",
        "introduction"
    };

    public static readonly IReadOnlySet<string> PublicIdentityFields = new HashSet<string>(StringComparer.Ordinal)
    {
        "callsign",
        "gameId",
        "avatarAssetId",
        "presence",
        "fleetName",
        "fleetCode",
        "fleetLogoAssetId",
        "fleetPositionTitle",
        "fleetPositionColor"
    };

    public static readonly IReadOnlySet<string> PrivateIdentityFields = new HashSet<string>(StringComparer.Ordinal)
    {
        "email",
        "accountId",
        "fleetRoleKey",
        "fleetPermissions",
        "serverShard",
        "exactLocation",
        "auditHistory"
    };

    public static int GetModuleMaximumSpan(string? moduleId)
    {
        if (moduleId is null)
        {
            return ColumnCount;
        }

        return moduleId switch
        {
            "skilled-roles" => 2,
            "favorite-ships" or "hangar-summary" => ColumnCount,
            _ => 1
        };
    }

    public static PersonalProfilePublicFleetAffiliation CreatePublicFleetAffiliation(
        string? fleetName,
        string? fleetCode,
        string? fleetLogoAssetId,
        string? positionTitle,
        string? positionColor)
    {
        if (string.IsNullOrWhiteSpace(fleetName))
        {
            return PersonalProfilePublicFleetAffiliation.None;
        }

        return new PersonalProfilePublicFleetAffiliation(
            fleetName.Trim(),
            (fleetCode ?? "").Trim(),
            NormalizePublicAssetId(fleetLogoAssetId),
            string.IsNullOrWhiteSpace(positionTitle) ? "组织成员" : positionTitle.Trim(),
            NormalizeColor(positionColor));
    }

    public static PersonalProfileV2MigrationPreview PreviewV2Migration(
        IEnumerable<PersonalProfileModuleSetting>? source)
    {
        var occupied = new bool[TargetVisibleCellCount];
        var displayed = new List<PersonalProfileModuleSetting>();
        var overflow = new List<string>();
        var candidates = (source ?? [])
            .Where(module => module.IsVisible)
            .Where(module => !LegacyModulesMovedToFixedSections.Contains(module.Id))
            .OrderBy(module => module.Position < 0 ? int.MaxValue : module.Position)
            .ThenBy(module => module.Order)
            .ToArray();

        foreach (var candidate in candidates)
        {
            var span = Math.Clamp(
                candidate.Span,
                1,
                Math.Min(ColumnCount, GetModuleMaximumSpan(candidate.Id)));
            var position = displayed.Count < MaxVisibleModuleCount
                ? FindFirstPosition(occupied, span)
                : -1;
            if (position < 0)
            {
                overflow.Add(candidate.Id);
                continue;
            }

            for (var offset = 0; offset < span; offset++)
            {
                occupied[position + offset] = true;
            }

            displayed.Add(candidate with
            {
                Span = span,
                Position = position,
                Order = displayed.Count
            });
        }

        return new PersonalProfileV2MigrationPreview(displayed.ToArray(), overflow.ToArray());
    }

    private static int FindFirstPosition(bool[] occupied, int span)
    {
        for (var position = 0; position < occupied.Length; position++)
        {
            if (position % ColumnCount + span > ColumnCount || position + span > occupied.Length)
            {
                continue;
            }

            var available = true;
            for (var offset = 0; offset < span; offset++)
            {
                if (occupied[position + offset])
                {
                    available = false;
                    break;
                }
            }

            if (available)
            {
                return position;
            }
        }

        return -1;
    }

    private static string? NormalizePublicAssetId(string? value)
    {
        var normalized = (value ?? "").Trim();
        if (normalized.Length is 0 or > 160 ||
            normalized.Contains('/') ||
            normalized.Contains('\\') ||
            normalized.Contains(':'))
        {
            return null;
        }

        return normalized;
    }

    private static string? NormalizeColor(string? value)
    {
        var normalized = (value ?? "").Trim();
        if (normalized.Length != 7 || normalized[0] != '#')
        {
            return null;
        }

        return normalized.Skip(1).All(Uri.IsHexDigit) ? normalized.ToUpperInvariant() : null;
    }
}
