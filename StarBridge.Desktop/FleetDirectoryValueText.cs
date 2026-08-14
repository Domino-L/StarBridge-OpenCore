namespace StarBridge.Desktop;

internal enum FleetDirectoryMissingValueKind
{
    HiddenByPublisher,
    MissingInput,
    EmptyStatistic,
    UnrecognizedInput
}

internal static class FleetDirectoryValueText
{
    internal static string Format(FleetDirectoryMissingValueKind kind) => kind switch
    {
        FleetDirectoryMissingValueKind.HiddenByPublisher => "未公开",
        FleetDirectoryMissingValueKind.MissingInput => "未提供",
        FleetDirectoryMissingValueKind.EmptyStatistic => "暂无数据",
        FleetDirectoryMissingValueKind.UnrecognizedInput => "无法识别",
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unreviewed fleet-directory value state.")
    };
}
