namespace StarBridge.Desktop;

internal enum FleetManagementOverviewTarget
{
    None,
    Applications,
    Announcement,
    Profile,
    Log
}

internal sealed record FleetManagementOverviewPriority(
    string Title,
    string Description,
    string ActionText,
    FleetManagementOverviewTarget Target,
    bool RequiresAttention);

internal static class FleetManagementOverviewPresentation
{
    public static FleetManagementOverviewPriority BuildPriority(
        int pendingApplicationCount,
        bool hasDescription,
        bool canReviewApplications,
        bool canEditProfile,
        bool canViewLogs)
    {
        if (pendingApplicationCount > 0 && canReviewApplications)
        {
            return new FleetManagementOverviewPriority(
                $"{pendingApplicationCount} 个加入申请等待处理",
                "及时审核申请，让新成员更快获得明确结果。",
                "处理申请",
                FleetManagementOverviewTarget.Applications,
                RequiresAttention: true);
        }

        if (!hasDescription && canEditProfile)
        {
            return new FleetManagementOverviewPriority(
                "组织介绍尚未完善",
                "补充组织定位与活动方式，帮助成员和访客快速了解组织。",
                "完善资料",
                FleetManagementOverviewTarget.Profile,
                RequiresAttention: true);
        }

        if (canViewLogs)
        {
            return new FleetManagementOverviewPriority(
                "当前没有待处理事项",
                "组织资料、公告与加入申请均处于正常状态。",
                "查看管理记录",
                FleetManagementOverviewTarget.Log,
                RequiresAttention: false);
        }

        return new FleetManagementOverviewPriority(
            "当前没有待处理事项",
            "你可以通过下方入口继续维护有权限管理的内容。",
            "",
            FleetManagementOverviewTarget.None,
            RequiresAttention: false);
    }
}
