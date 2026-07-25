namespace StarBridge.Desktop;

internal enum PersonalProfileViewerMode
{
    Owner,
    Visitor
}

internal sealed record PersonalProfilePresentationState(
    PersonalProfileViewerMode ViewerMode,
    bool IsEditing,
    bool CanViewProfile,
    bool ShowOwnerControls,
    bool ShowVisibilityEditor,
    bool ShowVisitorPreviewBanner,
    bool ShowPrivateVisitorState,
    bool ShowIdentityDetails,
    bool ShowFixedInformation,
    bool ShowModules,
    bool ShowModuleEmptySlots)
{
    public bool IsOwner => ViewerMode == PersonalProfileViewerMode.Owner;
    public bool IsVisitor => ViewerMode == PersonalProfileViewerMode.Visitor;
}

/// <summary>
/// Produces one presentation contract for both the owner and visitor views.
/// The UI renderer consumes this state instead of maintaining separate pages.
/// </summary>
internal static class PersonalProfilePresentationPolicy
{
    public static PersonalProfilePresentationState Build(
        PersonalProfileViewerMode viewerMode,
        bool isEditing,
        bool isProfilePublic,
        bool showVisitorPreviewBanner = false)
    {
        var isOwner = viewerMode == PersonalProfileViewerMode.Owner;
        var effectiveEditing = isOwner && isEditing;
        var canViewProfile = PersonalProfileVisibilityPolicy.CanViewProfile(isOwner, isProfilePublic);

        return new PersonalProfilePresentationState(
            viewerMode,
            effectiveEditing,
            canViewProfile,
            ShowOwnerControls: isOwner && !effectiveEditing,
            ShowVisibilityEditor: effectiveEditing,
            ShowVisitorPreviewBanner: !isOwner && showVisitorPreviewBanner,
            ShowPrivateVisitorState: !isOwner && !canViewProfile,
            ShowIdentityDetails: canViewProfile,
            ShowFixedInformation: canViewProfile,
            ShowModules: canViewProfile,
            ShowModuleEmptySlots: effectiveEditing && canViewProfile);
    }
}

internal static class PersonalProfileAvailabilityPresentation
{
    public static string FormatSummary(
        PersonalProfileSettings settings,
        PersonalProfileViewerMode viewerMode)
    {
        if (viewerMode == PersonalProfileViewerMode.Visitor && !settings.ShowOnlineTime)
        {
            return "未公开";
        }

        var windows = settings.AvailabilityWindows ?? [];
        if (windows.Length == 0)
        {
            return "未填写";
        }

        var summaries = windows
            .Select(FormatWindow)
            .Where(summary => !string.IsNullOrWhiteSpace(summary))
            .ToArray();

        return summaries.Length == 0
            ? "未填写"
            : string.Join(" · ", summaries);
    }

    private static string? FormatWindow(PersonalProfileAvailabilityWindowSetting window)
    {
        if (!TimeOnly.TryParseExact(
                window.StartTime,
                "HH:mm",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None,
                out var start) ||
            !TimeOnly.TryParseExact(
                window.EndTime,
                "HH:mm",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None,
                out var end))
        {
            return null;
        }

        var timeText = end <= start
            ? $"{window.StartTime} - 次日 {window.EndTime}"
            : $"{window.StartTime} - {window.EndTime}";
        return $"{FormatDays(window.Days)} {timeText}";
    }

    private static string FormatDays(IEnumerable<int>? values)
    {
        var days = (values ?? []).Distinct().Order().ToArray();
        if (days.Length == 7)
        {
            return "每天";
        }

        if (days.SequenceEqual([1, 2, 3, 4, 5]))
        {
            return "工作日";
        }

        if (days.SequenceEqual([0, 6]))
        {
            return "周末";
        }

        string[] labels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
        return days.Length == 0
            ? "未选日期"
            : string.Join("、", days.Where(day => day is >= 0 and <= 6).Select(day => labels[day]));
    }
}
