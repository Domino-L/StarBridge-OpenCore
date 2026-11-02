using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Communities;
namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private AchievementIdeaImageBridge? _achievementIdeaImages;
    public void ConfigureAchievementIdeaImagePicker(ICommunityLogoPicker picker)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        if (_achievementIdeaImages is not null) throw new InvalidOperationException("Achievement image picker already configured.");
        _achievementIdeaImages = new(picker, () => (_host.CurrentContext, _host.Generation));
        _host.AccountChanged += InvalidateAchievementIdeaImages;
    }
    private void InvalidateAchievementIdeaImages(long _) => _achievementIdeaImages?.Invalidate();
}
