namespace StarBridge.Desktop;

public readonly record struct AccountIdentityPresentation(
    string GameName,
    string PlayerId,
    string Status,
    bool HasMismatch)
{
    public static AccountIdentityPresentation Resolve(
        AccountRuntimeState accountState,
        bool scmGameIdentityVerified,
        string? scmGameIdentityHandle,
        string? detectedGameName,
        string? detectedPlayerId,
        bool allowExpiredOfflineCache,
        string language)
    {
        var scmHandle = Normalize(scmGameIdentityHandle);
        var detectedName = Normalize(detectedGameName);
        var playerId = Normalize(detectedPlayerId);
        var hasIdentityAccess = accountState.IsAuthenticated || allowExpiredOfflineCache;

        if (!hasIdentityAccess)
        {
            return new AccountIdentityPresentation(
                "请登录后查看",
                "请登录后查看",
                "浏览模式",
                HasMismatch: false);
        }

        var hasMismatch =
            accountState.ScmAuthenticated &&
            scmGameIdentityVerified &&
            scmHandle is not null &&
            detectedName is not null &&
            !string.Equals(scmHandle, detectedName, StringComparison.OrdinalIgnoreCase);
        if (hasMismatch)
        {
            return new AccountIdentityPresentation(
                scmHandle!,
                playerId ?? "身份不一致",
                "游戏身份不一致",
                HasMismatch: true);
        }

        if (accountState.ScmAuthenticated && scmGameIdentityVerified)
        {
            return new AccountIdentityPresentation(
                scmHandle ?? detectedName ?? "SCM 游戏身份已验证",
                playerId ?? "SCM 已验证",
                "SCM 游戏身份已验证",
                HasMismatch: false);
        }

        if (detectedName is not null)
        {
            return new AccountIdentityPresentation(
                detectedName,
                playerId ?? "等待识别游戏 ID",
                allowExpiredOfflineCache && !accountState.IsAuthenticated
                    ? "离线资料"
                    : language == "zh" ? "已缓存身份" : "Cached Identity",
                HasMismatch: false);
        }

        return new AccountIdentityPresentation(
            language == "zh" ? "等待游戏日志身份信息" : "Waiting for Game.log identity",
            "等待识别游戏 ID",
            language == "zh" ? "需要身份信息" : "Identity Required",
            HasMismatch: false);
    }

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
