namespace StarBridge.Desktop;

internal enum FleetDirectoryMemberScaleKind
{
    Small,
    Medium,
    Large,
    VeryLarge
}

internal static class FleetDirectoryMemberScale
{
    internal static FleetDirectoryMemberScaleKind Classify(int totalMembers) =>
        totalMembers switch
        {
            <= 10 => FleetDirectoryMemberScaleKind.Small,
            <= 50 => FleetDirectoryMemberScaleKind.Medium,
            < 300 => FleetDirectoryMemberScaleKind.Large,
            _ => FleetDirectoryMemberScaleKind.VeryLarge
        };

    internal static string Format(FleetDirectoryMemberScaleKind kind) =>
        kind switch
        {
            FleetDirectoryMemberScaleKind.Small => "小型舰队",
            FleetDirectoryMemberScaleKind.Medium => "中型舰队",
            FleetDirectoryMemberScaleKind.Large => "大型舰队",
            FleetDirectoryMemberScaleKind.VeryLarge => "超大型舰队",
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unsupported fleet directory member scale.")
        };
}
