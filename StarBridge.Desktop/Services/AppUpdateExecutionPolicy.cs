namespace StarBridge.Desktop;

internal static class AppUpdateExecutionPolicy
{
    internal const string DeveloperBuildMessage =
        "调试版本不参与应用内更新。请重新构建项目以获取最新开发内容。";

    internal static bool IsCurrentBuildAllowed =>
        IsInAppUpdateAllowedForBuild(IsDebugBuild);

    internal static bool IsInAppUpdateAllowedForBuild(bool isDebugBuild) =>
        !isDebugBuild;

    private static bool IsDebugBuild
    {
        get
        {
#if DEBUG
            return true;
#else
            return false;
#endif
        }
    }
}
